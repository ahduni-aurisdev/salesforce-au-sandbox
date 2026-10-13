public with sharing class CDCProgramLinesController {

    // ── Fetch existing lines for an Opportunity ──────────────────────────
    @AuraEnabled(cacheable=true)
    public static List<Drive_Program_Line__c> getLines(Id opportunityId) {
        return [
            SELECT Id, Name, Program__c, AOI__c,
                   Expected_Students__c, Registered_Students__c,
                   Appeared_Students__c, Shortlisted_Students__c,
                   Selected_Students__c, Offer_Accepted__c,
                   CTC_Offered__c, Remarks__c
            FROM Drive_Program_Line__c
            WHERE Opportunity__c = :opportunityId
            ORDER BY Program__c, AOI__c
        ];
    }

    // ── Get full Program → AOI map from Salesforce field metadata ────────
    // Returns { 'CSE': [{label,value},...], 'MBA': [...], ... }
    @AuraEnabled(cacheable=true)
    public static Map<String, List<Map<String, String>>> getAllAOIOptions() {
        return buildAOIMap();
    }

    // ── Get AOI options for a single Program (from metadata) ─────────────
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getAOIOptions(String program) {
        Map<String, List<Map<String, String>>> allMap = buildAOIMap();
        return allMap.containsKey(program)
            ? allMap.get(program)
            : new List<Map<String, String>>();
    }

    // ── Get Program picklist options from Salesforce metadata ────────────
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getProgramOptions() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        Schema.DescribeFieldResult fieldDesc = Drive_Program_Line__c.Program__c.getDescribe();
        for (Schema.PicklistEntry entry : fieldDesc.getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new Map<String, String>{
                    'label' => entry.getLabel(),
                    'value' => entry.getValue()
                });
            }
        }
        return options;
    }

    // ── Save lines (upsert) ──────────────────────────────────────────────
    @AuraEnabled
    public static List<Drive_Program_Line__c> saveLines(
        Id opportunityId,
        List<Drive_Program_Line__c> lines
    ) {
        try {
            // Opportunity__c is a non-reparentable Master-Detail field: it can only
            // be set on insert. Setting it on an update (even to the same value)
            // throws "Field is not writeable", so only stamp it on new lines.
            for (Drive_Program_Line__c line : lines) {
                if (line.Id == null) {
                    line.Opportunity__c = opportunityId;
                }
            }

            // Validate: no duplicate Program+AOI on same opportunity
            Set<String> keys = new Set<String>();
            for (Drive_Program_Line__c line : lines) {
                String key = line.Program__c + '|' + line.AOI__c;
                if (keys.contains(key)) {
                    AuraHandledException auraEx = new AuraHandledException(
                        'Duplicate entry: ' + line.Program__c + ' – ' + line.AOI__c +
                        '. Each Program and AOI combination must be unique per drive.'
                    );
                    auraEx.setMessage(auraEx.getMessage());
                    throw auraEx;
                }
                keys.add(key);
            }

            // Validate student count logic
            for (Drive_Program_Line__c line : lines) {
                if (line.Appeared_Students__c != null &&
                    line.Registered_Students__c != null &&
                    line.Appeared_Students__c > line.Registered_Students__c) {
                    AuraHandledException auraEx = new AuraHandledException(
                        line.Program__c + ' – ' + line.AOI__c +
                        ': Appeared cannot exceed Registered.'
                    );
                    auraEx.setMessage(auraEx.getMessage());
                    throw auraEx;
                }
                if (line.Selected_Students__c != null &&
                    line.Appeared_Students__c != null &&
                    line.Selected_Students__c > line.Appeared_Students__c) {
                    AuraHandledException auraEx = new AuraHandledException(
                        line.Program__c + ' – ' + line.AOI__c +
                        ': Selected cannot exceed Appeared.'
                    );
                    auraEx.setMessage(auraEx.getMessage());
                    throw auraEx;
                }
                if (line.Offer_Accepted__c != null &&
                    line.Selected_Students__c != null &&
                    line.Offer_Accepted__c > line.Selected_Students__c) {
                    AuraHandledException auraEx = new AuraHandledException(
                        line.Program__c + ' – ' + line.AOI__c +
                        ': Offer Accepted cannot exceed Selected.'
                    );
                    auraEx.setMessage(auraEx.getMessage());
                    throw auraEx;
                }
            }

            upsert lines;
            return lines;

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            AuraHandledException auraEx = new AuraHandledException('Save failed: ' + e.getMessage());
            auraEx.setMessage('Save failed: ' + e.getMessage());
            throw auraEx;
        }
    }

    // ── Delete a single line ─────────────────────────────────────────────
    @AuraEnabled
    public static void deleteLine(Id lineId) {
        try {
            delete [SELECT Id FROM Drive_Program_Line__c WHERE Id = :lineId LIMIT 1];
        } catch (Exception e) {
            AuraHandledException auraEx = new AuraHandledException('Delete failed: ' + e.getMessage());
            auraEx.setMessage('Delete failed: ' + e.getMessage());
            throw auraEx;
        }
    }

    // ── Private: build Program → AOI map from Salesforce field metadata ──
    // Reads the dependent picklist relationship between Program__c and AOI__c.
    // Falls back to hardcoded map if the dependent picklist isn't configured in the org.
    private static Map<String, List<Map<String, String>>> buildAOIMap() {
        Map<String, List<Map<String, String>>> result = new Map<String, List<Map<String, String>>>();

        // Step 1: index Program__c values by their picklist position
        Schema.DescribeFieldResult programDesc = Drive_Program_Line__c.Program__c.getDescribe();
        List<Schema.PicklistEntry> programEntries = programDesc.getPicklistValues();
        Map<Integer, String> indexToProgram = new Map<Integer, String>();
        for (Integer i = 0; i < programEntries.size(); i++) {
            if (programEntries[i].isActive()) {
                indexToProgram.put(i, programEntries[i].getValue());
                result.put(programEntries[i].getValue(), new List<Map<String, String>>());
            }
        }

        // Step 2: read AOI__c entries and decode their validFor bitmask
        Schema.DescribeFieldResult aoiDesc = Drive_Program_Line__c.AOI__c.getDescribe();
        for (Schema.PicklistEntry aoiEntry : aoiDesc.getPicklistValues()) {
            if (!aoiEntry.isActive()) continue;

            // Extract the validFor bitmask via JSON serialization (only supported way in Apex)
            Map<String, Object> entryJson = (Map<String, Object>)
                JSON.deserializeUntyped(JSON.serialize(aoiEntry));
            String validForEncoded = (String) entryJson.get('validFor');

            if (String.isBlank(validForEncoded)) continue;

            String hexStr = EncodingUtil.convertToHex(
                EncodingUtil.base64Decode(validForEncoded)
            );

            for (Integer idx : indexToProgram.keySet()) {
                if (isBitSet(hexStr, idx)) {
                    result.get(indexToProgram.get(idx)).add(new Map<String, String>{
                        'label' => aoiEntry.getLabel(),
                        'value' => aoiEntry.getValue()
                    });
                }
            }
        }

        // Step 3: if no entries were mapped (dependent picklist not configured),
        // fall back to hardcoded map so the component still works
        Boolean hasAnyMapping = false;
        for (List<Map<String, String>> vals : result.values()) {
            if (!vals.isEmpty()) { hasAnyMapping = true; break; }
        }
        if (!hasAnyMapping) {
            return buildAOIMapFallback();
        }

        return result;
    }

    // Checks whether bit at position bitIndex is set in the hex-encoded bitmask
    @TestVisible
    private static Boolean isBitSet(String hexStr, Integer bitIndex) {
        Integer byteIndex  = bitIndex / 8;
        Integer bitInByte  = 7 - Math.mod(bitIndex, 8);
        Integer byteStart  = byteIndex * 2;
        if (byteStart + 2 > hexStr.length()) return false;
        Integer byteVal = hexToInt(hexStr.substring(byteStart, byteStart + 2));
        return (byteVal & intPow(2, bitInByte)) != 0;
    }

    @TestVisible
    private static Integer hexToInt(String hex) {
        Integer val = 0;
        for (Integer i = 0; i < hex.length(); i++) {
            val *= 16;
            String c = hex.substring(i, i + 1).toLowerCase();
            if      (c == 'a') val += 10;
            else if (c == 'b') val += 11;
            else if (c == 'c') val += 12;
            else if (c == 'd') val += 13;
            else if (c == 'e') val += 14;
            else if (c == 'f') val += 15;
            else                val += Integer.valueOf(c);
        }
        return val;
    }

    @TestVisible
    private static Integer intPow(Integer base, Integer exp) {
        Integer result = 1;
        for (Integer i = 0; i < exp; i++) result *= base;
        return result;
    }

    @TestVisible
    private static Map<String, List<Map<String, String>>> buildAOIMapFallback() {
        Map<String, List<String>> aoiByProgram = new Map<String, List<String>>{
            'CSE'    => new List<String>{'Software Development','Data Science','Machine Learning','Cloud Computing','Cybersecurity','DevOps','Product Management','Others'},
            'CS'     => new List<String>{'Software Development','Data Science','Machine Learning','Cloud Computing','Cybersecurity','DevOps','Product Management','Others'},
            'BS'     => new List<String>{'Software Development','Data Science','Machine Learning','Research','Analytics','Others'},
            'iMSC'   => new List<String>{'Software Development','Data Science','Machine Learning','Cloud Computing','Research','Analytics','Others'},
            'Mech'   => new List<String>{'Design and Manufacturing','Automotive','Robotics','Project Engineering','Others'},
            'MBA'    => new List<String>{'Finance','Human Resources','Marketing','Sales','Operations','Business Development','Strategy and Consulting','Product Management','Others'},
            'iMBA'   => new List<String>{'Finance','Human Resources','Marketing','Sales','Operations','Business Development','Strategy and Consulting','Others'},
            'BBA'    => new List<String>{'Finance','Human Resources','Marketing','Sales','Accounting','Banking','Others'},
            'Bcom'   => new List<String>{'Finance','Accounting','Sales','Banking','Others'},
            'Eco'    => new List<String>{'Finance','Accounting','Banking','Analytics','Research','Others'},
            'SAS'    => new List<String>{'Research','Analytics','Data Science','Others'},
            'Others' => new List<String>{'General','Others'}
        };

        Map<String, List<Map<String, String>>> result = new Map<String, List<Map<String, String>>>();
        for (String prog : aoiByProgram.keySet()) {
            List<Map<String, String>> opts = new List<Map<String, String>>();
            for (String aoi : aoiByProgram.get(prog)) {
                opts.add(new Map<String, String>{ 'label' => aoi, 'value' => aoi });
            }
            result.put(prog, opts);
        }
        return result;
    }
}