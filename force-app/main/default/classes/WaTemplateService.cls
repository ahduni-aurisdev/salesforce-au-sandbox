/**
 * @description Business operations of the WhatsApp Template Manager: list accounts, list templates (with
 *              cursor pagination built through the Named Credential, never following paging.next because it
 *              embeds the token), create a template, and upload a header sample with Meta's Resumable Upload.
 *              Only WABA IDs that are present and Active in WA_Account__mdt can be used.
 *              Limits: list = at most MAX_PAGES callouts; create = 1 callout + 1 DML; upload = 2 callouts and
 *              a file of at most 4 MB (6 MB synchronous heap; the request body is held once in heap).
 * @author AU Development Team
 * @date 2026-11-26
 * @version 1.0
 * @lastModified 2026-11-27
 */
public with sharing class WaTemplateService {
    @TestVisible
    private static final String TEMPLATE_FIELDS = 'id,name,status,category,language,components,rejected_reason,quality_score';
    @TestVisible
    private static final Integer PAGE_SIZE = 100;
    @TestVisible
    private static final Integer MAX_PAGES = 10;
    /** Stop paging when heap use passes this share of the limit, so serializing the response can't fail. */
    private static final Decimal MAX_HEAP_SHARE = 0.5;
    private static final Integer LIST_TIMEOUT_MS = 20000;
    private static final Integer CREATE_TIMEOUT_MS = 30000;
    private static final Integer UPLOAD_START_TIMEOUT_MS = 20000;
    private static final Integer UPLOAD_TIMEOUT_MS = 60000;

    private static final Integer MAX_UPLOAD_BYTES = 4 * 1024 * 1024;
    /** Tests lower this so they don't need a 4 MB blob (more than the test heap allows alongside the request). */
    @TestVisible
    private static Integer maxUploadBytes = MAX_UPLOAD_BYTES;
    private static final Integer FILE_NAME_MAX = 200;
    private static final Map<String, Set<String>> EXTENSIONS_BY_TYPE = new Map<String, Set<String>>{
        'image/jpeg' => new Set<String>{ 'jpg', 'jpeg' },
        'image/jpg' => new Set<String>{ 'jpg', 'jpeg' },
        'image/png' => new Set<String>{ 'png' },
        'video/mp4' => new Set<String>{ 'mp4' },
        'application/pdf' => new Set<String>{ 'pdf' }
    };

    private static final Pattern WABA_ID_PATTERN = Pattern.compile('^[0-9]{5,25}$');
    private static final Pattern APP_ID_PATTERN = Pattern.compile('^[0-9]{5,25}$');
    private static final Pattern UPLOAD_SESSION_PATTERN = Pattern.compile('^upload:[A-Za-z0-9+/=_:.%?\\-]+$');
    private static final Pattern UNSAFE_FILE_NAME_CHARS = Pattern.compile('[^A-Za-z0-9._ \\-]');

    private static final String ACTION_CREATE = 'Create';
    private static final String LOG_NAME = 'WaTemplateManager';
    private static final String CLASS_NAME = 'WaTemplateService';

    /**
     * @description Active accounts for the number switcher.
     * @return accounts response
     */
    public static WaTemplateModels.AccountsResponse listAccounts() {
        WaTemplateModels.AccountsResponse response = new WaTemplateModels.AccountsResponse();
        for (WA_Account__mdt account : WaConfigSelector.getActiveAccounts()) {
            String label = String.isBlank(account.Display_Label__c) ? account.MasterLabel : account.Display_Label__c;
            response.accounts.add(new WaTemplateModels.AccountDto(account.WABA_Id__c.trim(), label));
        }
        return response;
    }

    /**
     * @description Throws 400/403 unless the WABA ID is well-formed and Active in WA_Account__mdt.
     * @param wabaId WABA ID from the request
     * @return the account record
     */
    public static WA_Account__mdt requireActiveAccount(String wabaId) {
        if (String.isBlank(wabaId) || !WABA_ID_PATTERN.matcher(wabaId).matches()) {
            throw WaException.of(400, 'Choose a WhatsApp number first.');
        }
        WA_Account__mdt account = WaConfigSelector.findActiveAccount(wabaId);
        if (account == null) {
            throw WaException.of(403, 'This WhatsApp account is not enabled in Salesforce. Ask your Salesforce admin to add it to WA Account and mark it Active.');
        }
        return account;
    }

    /**
     * @description All templates of one WABA, following paging.cursors.after up to MAX_PAGES.
     * @param wabaId active WABA ID
     * @return templates response; truncated = true when more pages existed than could be fetched
     */
    public static WaTemplateModels.TemplatesResponse listTemplates(String wabaId) {
        requireActiveAccount(wabaId);
        String basePath = WaGraphClient.versionPath() + '/' + wabaId + '/message_templates'
            + '?fields=' + encode(TEMPLATE_FIELDS) + '&limit=' + PAGE_SIZE;

        WaTemplateModels.TemplatesResponse response = new WaTemplateModels.TemplatesResponse();
        String afterCursor;
        Integer pages = 0;
        do {
            String path = afterCursor == null ? basePath : basePath + '&after=' + encode(afterCursor);
            Map<String, Object> page = WaGraphClient.get(path, LIST_TIMEOUT_MS);
            pages++;
            for (Object item : asList(page.get('data'))) {
                response.templates.add(toTemplate(asMap(item)));
            }
            afterCursor = nextCursor(page);
            Boolean heapNearlyFull = Limits.getHeapSize() > Limits.getLimitHeapSize() * MAX_HEAP_SHARE;
            if (afterCursor != null && (pages >= MAX_PAGES || heapNearlyFull || !WaGraphClient.canCallAgain())) {
                response.truncated = true;
                afterCursor = null;
            }
        } while (afterCursor != null);
        response.count = response.templates.size();
        return response;
    }

    /**
     * @description Validates and submits a new template, then writes a WA_Template_Log__c record.
     * @param wabaId active WABA ID
     * @param requestBody JSON body from the page
     * @return create response with Meta's id, status and category
     */
    public static WaTemplateModels.CreateResponse createTemplate(String wabaId, String requestBody) {
        requireActiveAccount(wabaId);
        Map<String, Object> input;
        try {
            Object parsed = String.isBlank(requestBody) ? null : JSON.deserializeUntyped(requestBody);
            input = parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : null;
        } catch (JSONException parseError) {
            input = null;
        }
        if (input == null) {
            throw WaException.of(400, 'The template data could not be read. Reload the page and try again.');
        }
        Map<String, Object> payload = WaTemplateValidator.validateAndBuild(input);
        Map<String, Object> result = WaGraphClient.postJson(
            WaGraphClient.versionPath() + '/' + wabaId + '/message_templates',
            JSON.serialize(payload),
            CREATE_TIMEOUT_MS
        );

        WaTemplateModels.CreateResponse response = new WaTemplateModels.CreateResponse();
        response.id = asText(result.get('id'));
        response.status = asText(result.get('status'));
        response.category = asText(result.get('category'));
        response.name = (String) payload.get('name');
        response.language = (String) payload.get('language');
        if (String.isBlank(response.id)) {
            throw WaException.logged(WaException.HTTP_UPSTREAM_FAILED, 'Meta did not confirm the template. Refresh the list in a minute to check whether it was created.', 'Create returned no id for ' + response.name);
        }
        writeLog(wabaId, response);
        return response;
    }

    /**
     * @description Uploads a header sample with Meta's Resumable Upload and returns the header handle.
     *              Step 1 (Bearer): POST /{app_id}/uploads -> id "upload:...". Step 2 (OAuth, file_offset 0):
     *              POST /{id} with the raw bytes -> h.
     * @param body file bytes
     * @param fileName original file name
     * @param fileType MIME type
     * @return upload response with header_handle
     */
    public static WaTemplateModels.UploadResponse uploadSample(Blob body, String fileName, String fileType) {
        if (body == null || body.size() == 0) {
            throw WaException.of(400, 'Choose a file to upload.');
        }
        if (body.size() > maxUploadBytes) {
            throw WaException.of(413, 'This file is ' + megabytes(body.size()) + ' MB. The limit here is ' + megabytes(maxUploadBytes) + ' MB. Compress it and try again.');
        }
        String type = fileType == null ? '' : fileType.trim().toLowerCase();
        if (!EXTENSIONS_BY_TYPE.containsKey(type)) {
            throw WaException.of(415, 'Only JPG or PNG images, MP4 videos and PDF documents can be used as header samples.');
        }
        String safeName = sanitizeFileName(fileName);
        String extension = safeName.contains('.') ? safeName.substringAfterLast('.').toLowerCase() : '';
        if (!EXTENSIONS_BY_TYPE.get(type).contains(extension)) {
            throw WaException.of(415, 'The file name must end in .' + String.join(new List<String>(EXTENSIONS_BY_TYPE.get(type)), ' or .') + ' for this file type.');
        }

        WA_Setting__mdt setting = WaConfigSelector.getSetting();
        String appId = setting == null ? null : setting.App_Id__c;
        if (String.isBlank(appId) || !APP_ID_PATTERN.matcher(appId.trim()).matches()) {
            throw WaException.logged(503, 'The Meta App ID is not set in WA Setting (Default). Ask your Salesforce admin to add it.', 'App_Id__c missing or invalid');
        }
        String version = WaGraphClient.versionPath();
        String metaType = type == 'image/jpg' ? 'image/jpeg' : type;

        Map<String, Object> session = WaGraphClient.postEmpty(
            version + '/' + appId.trim() + '/uploads?file_name=' + encode(safeName) + '&file_length=' + body.size() + '&file_type=' + encode(metaType),
            UPLOAD_START_TIMEOUT_MS
        );
        String sessionId = asText(session.get('id'));
        if (String.isBlank(sessionId) || !UPLOAD_SESSION_PATTERN.matcher(sessionId).matches()) {
            throw WaException.logged(WaException.HTTP_UPSTREAM_FAILED, 'Meta did not start the upload. Try again.', 'Unexpected upload session id format');
        }
        Map<String, Object> uploaded = WaGraphClient.postFile(version + '/' + sessionId, body, UPLOAD_TIMEOUT_MS);
        String handle = asText(uploaded.get('h'));
        if (String.isBlank(handle)) {
            throw WaException.logged(WaException.HTTP_UPSTREAM_FAILED, 'Meta did not return the uploaded file. Try again.', 'Upload returned no handle');
        }
        return new WaTemplateModels.UploadResponse(handle);
    }

    private static void writeLog(String wabaId, WaTemplateModels.CreateResponse created) {
        WA_Template_Log__c log = new WA_Template_Log__c(
            Template_Name__c = created.name.left(255),
            WABA_Id__c = wabaId,
            Language__c = created.language,
            Category__c = created.category == null ? null : created.category.left(30),
            Meta_Template_Id__c = created.id.left(40),
            Status__c = created.status == null ? null : created.status.left(40),
            Action__c = ACTION_CREATE
        );
        Database.SaveResult result = Database.insert(new List<WA_Template_Log__c>{ log }, false, AccessLevel.USER_MODE)[0];
        if (!result.isSuccess()) {
            List<String> messages = new List<String>();
            for (Database.Error error : result.getErrors()) {
                messages.add(error.getStatusCode() + ': ' + error.getMessage());
            }
            ZoomLogger.logFailure(LOG_NAME, CLASS_NAME, created.id, 'WA_Template_Log__c insert failed', String.join(messages, '; '));
        }
    }

    private static WaTemplateModels.TemplateDto toTemplate(Map<String, Object> raw) {
        WaTemplateModels.TemplateDto template = new WaTemplateModels.TemplateDto();
        template.id = asText(raw.get('id'));
        template.name = asText(raw.get('name'));
        template.status = asText(raw.get('status'));
        template.category = asText(raw.get('category'));
        template.language = asText(raw.get('language'));
        template.components = raw.get('components');
        template.rejected_reason = asText(raw.get('rejected_reason'));
        template.quality_score = raw.get('quality_score');
        return template;
    }

    /** Uses only paging.cursors.after, and only when Meta signals another page with paging.next. */
    private static String nextCursor(Map<String, Object> page) {
        Map<String, Object> paging = asMap(page.get('paging'));
        if (paging.get('next') == null) {
            return null;
        }
        String after = asText(asMap(paging.get('cursors')).get('after'));
        return String.isBlank(after) ? null : after;
    }

    private static String sanitizeFileName(String fileName) {
        String name = String.isBlank(fileName) ? '' : fileName.trim();
        Integer lastSeparator = Math.max(name.lastIndexOf('/'), name.lastIndexOf('\\'));
        if (lastSeparator >= 0) {
            name = name.substring(lastSeparator + 1);
        }
        name = UNSAFE_FILE_NAME_CHARS.matcher(name).replaceAll('_');
        if (String.isBlank(name)) {
            throw WaException.of(400, 'The file needs a name.');
        }
        return name.right(FILE_NAME_MAX);
    }

    private static String megabytes(Integer bytes) {
        return String.valueOf((Decimal.valueOf(bytes) / (1024 * 1024)).setScale(1));
    }

    private static String encode(String value) {
        return EncodingUtil.urlEncode(value, 'UTF-8');
    }

    private static String asText(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : new Map<String, Object>();
    }

    private static List<Object> asList(Object value) {
        return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
    }
}