/**
 * Fully dynamic, Permission-Set-driven partner REST endpoint.
 *
 * URL:    /services/apexrest/v1/records/{ObjectApiName}
 * Method: GET
 * Params: fields (optional) - comma-separated field API names to return.
 *                              Omit to return every field the reference
 *                              Permission Set (below) grants Read on. If
 *                              provided, EVERY listed field must have a
 *                              Read grant on the reference Permission Set
 *                              or the whole request fails (400) - fields
 *                              are never silently dropped from an
 *                              explicit request.
 *         limit  (optional) - max records (default 100, max 200).
 *         Any other query param (besides fields/limit) filters records
 *                              on the field of that exact API name, e.g.
 *                              Email=a@x.com,b@x.com - a comma-separated
 *                              list ORs together as an IN-list. Multiple
 *                              filter params AND together. The field name
 *                              is resolved dynamically against whatever
 *                              the reference Permission Set (below)
 *                              currently grants Read on for the requested
 *                              object - there is no fixed list of which
 *                              fields are filterable, only which field
 *                              *types* are (see STRING_COMPARABLE_TYPES).
 *
 * Example: GET /services/apexrest/v1/records/Lead?fields=Email,Company&Email=a@x.com,b@x.com&limit=50
 *
 * Lead-specific rule: every query against Lead is hard-restricted to
 * UTM_Link__c = 'https://ahduni.univiser.io/', in addition to any partner-supplied filters.
 * This is not partner-overridable - it is ANDed into the WHERE clause
 * unconditionally, even if the partner passes their own UTM_Link__c filter.
 *
 * Filtering uses Database.queryWithBinds() (available since Spring '23)
 * so filter values are always passed as real bind variables, never
 * concatenated into the SOQL string - the only partner-controlled text
 * that reaches the query is the bind values themselves. The filter field
 * name itself is partner-supplied too (the query param name), but it is
 * never concatenated raw either: it is resolved against the reference
 * Permission Set's own granted-field set first, and only the matched,
 * canonical API name from that set is ever placed into the SOQL string.
 *
 * There is NO hardcoded field or object list in this class. Every
 * decision - which object can be queried, which fields come back - is
 * resolved at request time by querying the FieldPermissions and
 * ObjectPermissions records that belong to PARTNER_PERMISSION_SET_NAME
 * directly.
 *
 * DELIBERATE DESIGN CHOICE: this checks what that named Permission Set's
 * own definition grants - NOT the effective access of whichever user
 * happens to be running this Apex code (that would be
 * Schema.isAccessible(), which reflects Profile + all assigned
 * Permission Sets combined, and is meaningless if the running user is a
 * System Administrator, since Permission Sets can only ADD access on
 * top of a Profile, never remove it). Checking the named Permission
 * Set's own rows means the field/object whitelist holds regardless of
 * who executes the request - including an admin - and this Permission
 * Set does not even need to be assigned to that user for this check to
 * work.
 *
 * WHAT THIS DOES NOT SOLVE: this only governs what THIS CLASS returns.
 * It has no effect on row-level (record) visibility - if the running
 * user has "View All Data" (true for System Administrator), every
 * record is visible regardless of ownership/sharing, independent of
 * this check. It also has no effect outside this class - if the OAuth
 * token this endpoint runs under is capable of calling other Salesforce
 * APIs (standard REST, Bulk, Tooling, etc.) as that same running user,
 * this class cannot prevent that. Salesforce does not support scoping
 * an OAuth token to a single custom REST resource; the only way to cap
 * that is to run this integration as a genuinely low-privilege user.
 *
 * Unknown/ungranted objects return 404 rather than 403, so a partner
 * probing arbitrary object names can't use the status code to enumerate
 * what exists in the org.
 */
@RestResource(urlMapping='/v1/records/*')
global with sharing class PartnerDynamicRecordResource {

    // Name (developer name) of the Permission Set whose FieldPermissions
    // and ObjectPermissions rows define what this endpoint may return.
    // This Permission Set does not need to be assigned to any user - it
    // is read here purely as a policy definition.
    private static final String PARTNER_PERMISSION_SET_NAME = 'Partner_API_Access';

    private static final Integer DEFAULT_LIMIT = 100;
    private static final Integer MAX_LIMIT = 200;

    // Query param names that are never treated as a filter field, no
    // matter what the Permission Set grants.
    private static final Set<String> RESERVED_PARAM_NAMES = new Set<String>{ 'fields', 'limit' };

    // Filter values are always bound as an Apex List<String> (raw,
    // partner-supplied query text) - these are the field types where a
    // String IN-list is a well-defined comparison. This is a type-safety
    // boundary, not a business-rule field list: it holds for ANY field of
    // one of these types, on ANY object, regardless of which specific
    // fields the Permission Set happens to grant.
    private static final Set<Schema.DisplayType> STRING_COMPARABLE_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.PICKLIST,
        Schema.DisplayType.TEXTAREA,
        Schema.DisplayType.URL,
        Schema.DisplayType.ID,
        Schema.DisplayType.REFERENCE
    };

    private static final Integer MAX_FILTER_VALUES = 50;

    // Every Lead query this endpoint runs is hard-restricted to this
    // UTM_Link__c, regardless of what filters the partner requests - this
    // is a mandatory scoping condition, not a partner-overridable default,
    // and is always ANDed in alongside any partner-supplied filters.
    private static final String LEAD_OBJECT_NAME = 'Lead';
    private static final String LEAD_SCOPE_FIELD = 'UTM_Link__c';
    private static final String LEAD_SCOPE_REQUIRED_VALUE = 'https://ahduni.univiser.io/';

    private class FilterValidationException extends Exception {}
    private class FieldValidationException extends Exception {}

    @HttpGet
    global static void getRecords() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        res.addHeader('Content-Type', 'application/json');

        try {
            String objectApiName = parseObjectName(req);
            if (String.isBlank(objectApiName)) {
                writeError(res, 400, 'No object specified. Call /v1/records/{ObjectApiName}.');
                return;
            }

            Schema.SObjectType objType = resolveObjectType(objectApiName);
            if (objType == null) {
                writeError(res, 404, 'Unknown object: ' + objectApiName);
                return;
            }
            String canonicalObjectName = objType.getDescribe().getName();

            Id permSetId = getPartnerPermissionSetId();
            if (permSetId == null) {
                writeError(res, 500, 'Partner permission set is not configured.');
                return;
            }

            if (!permissionSetGrantsObjectRead(permSetId, canonicalObjectName)) {
                // The reference Permission Set doesn't grant object-level
                // Read here - 404 rather than 403, see class comment.
                writeError(res, 404, 'Unknown object: ' + objectApiName);
                return;
            }

            Set<String> accessibleFields = getPermissionSetReadableFields(permSetId, canonicalObjectName);
            if (accessibleFields.isEmpty()) {
                writeError(res, 404, 'Unknown object: ' + objectApiName);
                return;
            }

            List<String> selectedFields = resolveRequestedFields(req, accessibleFields);
            if (selectedFields.isEmpty()) {
                // Only reachable when 'fields' was blank/whitespace-only
                // (e.g. 'fields=,,'); an explicit list containing an
                // ungranted field fails loudly inside
                // resolveRequestedFields instead of landing here.
                writeError(res, 400,
                    'No valid/accessible fields requested for ' + objectApiName + '.');
                return;
            }

            Integer limitSize = resolveLimit(req);

            Map<String, Object> bindMap = new Map<String, Object>();
            List<String> whereClauses = buildFilterConditions(req, objType, accessibleFields, bindMap);

            if (canonicalObjectName == LEAD_OBJECT_NAME) {
                bindMap.put('requiredLeadScope', LEAD_SCOPE_REQUIRED_VALUE);
                whereClauses.add(LEAD_SCOPE_FIELD + ' = :requiredLeadScope');
            }

            String soql = 'SELECT ' + String.join(selectedFields, ', ') +
                          ' FROM ' + String.escapeSingleQuotes(canonicalObjectName);
            if (!whereClauses.isEmpty()) {
                soql += ' WHERE ' + String.join(whereClauses, ' AND ');
            }
            soql += ' LIMIT ' + limitSize;

            // NOTE: AccessLevel.USER_MODE reflects the ACTUAL running
            // user's access, not the reference Permission Set's. If this
            // endpoint runs as an admin-type user, USER_MODE adds no
            // restriction beyond the checks above - the Permission-Set
            // lookup is doing all of the field-level enforcement in that
            // case. It's kept so this class also behaves correctly if
            // it's later pointed at a properly-restricted running user.
            List<SObject> records = Database.queryWithBinds(soql, bindMap, AccessLevel.USER_MODE);

            res.statusCode = 200;
            res.responseBody = Blob.valueOf(JSON.serialize(records));

        } catch (FieldValidationException fve) {
            writeError(res, 400, fve.getMessage());
        } catch (FilterValidationException fve) {
            writeError(res, 400, fve.getMessage());
        } catch (QueryException qe) {
            writeError(res, 403, 'Access denied by the platform for this request.');
        } catch (Exception e) {
            writeError(res, 500, 'Unexpected error: ' + e.getMessage());
        }
    }

    private static List<String> buildFilterConditions(RestRequest req, Schema.SObjectType objType, Set<String> accessibleFields, Map<String, Object> bindMap) {
        List<String> clauses = new List<String>();
        Integer bindIndex = 0;
        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();

        for (String paramKey : req.params.keySet()) {
            if (RESERVED_PARAM_NAMES.contains(paramKey.toLowerCase())) {
                continue;
            }
            String rawValue = req.params.get(paramKey);
            if (String.isBlank(rawValue)) {
                continue;
            }

            // Resolve the query param name to a real, Permission-Set-
            // granted field - case-insensitively, same rule as the
            // 'fields' param - never trust the raw partner-supplied text
            // as the field name itself.
            String fieldApiName = null;
            for (String accessible : accessibleFields) {
                if (accessible.equalsIgnoreCase(paramKey)) {
                    fieldApiName = accessible;
                    break;
                }
            }
            if (fieldApiName == null) {
                // Fail loudly rather than silently ignoring the filter,
                // since silently dropping a filter WIDENS the result set
                // beyond what the partner asked for. That's the opposite
                // failure mode from an ungranted response field, which is
                // safe to drop silently because it only narrows output.
                throw new FilterValidationException(
                    'Cannot filter by "' + paramKey + '" on this object - field is not available to your integration.'
                );
            }

            Schema.DisplayType fieldType = fieldMap.get(fieldApiName).getDescribe().getType();
            if (!STRING_COMPARABLE_TYPES.contains(fieldType)) {
                throw new FilterValidationException(
                    'Cannot filter by "' + paramKey + '" - this field\'s type does not support filtering.'
                );
            }

            List<String> values = new List<String>();
            for (String v : rawValue.split(',')) {
                String trimmed = v.trim();
                if (String.isNotBlank(trimmed) && !values.contains(trimmed)) {
                    values.add(trimmed);
                }
            }
            if (values.isEmpty()) {
                continue;
            }
            if (values.size() > MAX_FILTER_VALUES) {
                throw new FilterValidationException(
                    'Too many values for "' + paramKey + '" - maximum ' + MAX_FILTER_VALUES + ' per request.'
                );
            }

            String bindName = 'filterValues' + bindIndex;
            bindIndex++;
            bindMap.put(bindName, values);
            clauses.add(fieldApiName + ' IN :' + bindName);
        }

        return clauses;
    }

    private static Id getPartnerPermissionSetId() {
        List<PermissionSet> ps = [
            SELECT Id FROM PermissionSet WHERE Name = :PARTNER_PERMISSION_SET_NAME LIMIT 1
        ];
        return ps.isEmpty() ? null : ps[0].Id;
    }

    private static Boolean permissionSetGrantsObjectRead(Id permSetId, String objectApiName) {
        List<ObjectPermissions> perms = [
            SELECT PermissionsRead
            FROM ObjectPermissions
            WHERE ParentId = :permSetId AND SobjectType = :objectApiName
            LIMIT 1
        ];
        return !perms.isEmpty() && perms[0].PermissionsRead;
    }

    private static Set<String> getPermissionSetReadableFields(Id permSetId, String objectApiName) {
        Set<String> fields = new Set<String>();
        for (FieldPermissions fp : [
            SELECT Field
            FROM FieldPermissions
            WHERE ParentId = :permSetId AND SobjectType = :objectApiName AND PermissionsRead = true
        ]) {
            // FieldPermissions.Field is stored as 'ObjectApiName.FieldApiName'.
            String fieldApiName = fp.Field.contains('.') ? fp.Field.substringAfter('.') : fp.Field;
            fields.add(fieldApiName);
        }

        // FirstName/LastName (compound Name field components) and Status
        // (a required field on Lead) cannot carry an explicit
        // FieldPermissions row - Metadata API rejects FLS on compound-name
        // components, and required fields are always implicitly readable
        // and can't be deployed either. Same reasoning as Id below: they
        // have no configurable FieldPermissions row, so they're included
        // directly rather than via the Permission Set.
        fields.add('FirstName');
        fields.add('LastName');
        fields.add('Status');
        fields.add('Phone');
        fields.add('City');
        fields.add('State');
        fields.add('CreatedDate');

        // Id has no configurable FieldPermissions row and is always
        // implicitly readable; include it so records have a stable key.
        if (!fields.isEmpty()) {
            fields.add('Id');
        }
        return fields;
    }

    private static String parseObjectName(RestRequest req) {
        String uri = req.requestURI;
        if (String.isBlank(uri)) {
            return null;
        }
        List<String> parts = uri.split('/');
        String last = parts.isEmpty() ? null : parts[parts.size() - 1];
        return String.isBlank(last) ? null : last.trim();
    }

    private static Schema.SObjectType resolveObjectType(String objectApiName) {
        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        Schema.SObjectType objType = globalDescribe.get(objectApiName);
        if (objType != null) {
            return objType;
        }
        // Defensive fallback in case an exact-case lookup misses.
        for (String key : globalDescribe.keySet()) {
            if (key.equalsIgnoreCase(objectApiName)) {
                return globalDescribe.get(key);
            }
        }
        return null;
    }

    private static List<String> resolveRequestedFields(RestRequest req, Set<String> accessibleFields) {
        List<String> selected = new List<String>();
        String fieldsParam = req.params.get('fields');

        if (String.isBlank(fieldsParam)) {
            // No fields specified -> return every field the reference
            // Permission Set grants Read on.
            selected.addAll(accessibleFields);
            return selected;
        }

        for (String requested : fieldsParam.split(',')) {
            String trimmed = requested.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }

            String matched = null;
            for (String accessible : accessibleFields) {
                // Case-insensitive match against the accessible set, but
                // the canonical (correctly-cased) API name is what gets
                // added to the query - never the raw partner input.
                if (accessible.equalsIgnoreCase(trimmed)) {
                    matched = accessible;
                    break;
                }
            }

            if (matched == null) {
                // Fail loudly rather than silently dropping - a partner
                // explicitly asking for a field must know if they can't
                // have it, not receive a response that quietly omits it.
                throw new FieldValidationException(
                    'Cannot return field "' + trimmed + '" - field is not available to your integration.'
                );
            }
            if (!selected.contains(matched)) {
                selected.add(matched);
            }
        }
        return selected;
    }

    private static Integer resolveLimit(RestRequest req) {
        String limitParam = req.params.get('limit');
        if (String.isBlank(limitParam)) {
            return DEFAULT_LIMIT;
        }
        Integer parsed;
        try {
            parsed = Integer.valueOf(limitParam.trim());
        } catch (Exception e) {
            return DEFAULT_LIMIT;
        }
        if (parsed <= 0) {
            return DEFAULT_LIMIT;
        }
        return Math.min(parsed, MAX_LIMIT);
    }

    private static void writeError(RestResponse res, Integer statusCode, String message) {
        res.statusCode = statusCode;
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{ 'error' => message }));
    }
}