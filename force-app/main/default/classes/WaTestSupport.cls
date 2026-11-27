/**
 * @description Shared test setup for the WhatsApp Template Manager: in-memory configuration through the
 *              @TestVisible overrides (no dependency on real custom metadata or custom setting records),
 *              REST context builders and sample Meta payloads.
 * @author AU Development Team
 * @date 2026-11-26
 * @version 1.0
 * @lastModified 2026-11-26
 */
@IsTest
public class WaTestSupport {
    public static final String ADMIN_KEY = 'test-admin-key-7f3a9c';
    public static final String WABA_ACTIVE = '111111111111111';
    public static final String WABA_SECOND = '222222222222222';
    public static final String WABA_INACTIVE = '333333333333333';
    public static final String APP_ID = '987654321012345';
    public static final String GRAPH_VERSION = 'v27.0';

    /**
     * @description Feature on, admin key set, Default settings and three accounts (two active).
     */
    public static void configure() {
        FeatureFlagService.testOverrides.put(WaAuthService.FEATURE_FLAG, true);
        WaConfigSelector.adminKeyOverride = ADMIN_KEY;
        WaConfigSelector.settingOverride = new WA_Setting__mdt(App_Id__c = APP_ID, Graph_Version__c = GRAPH_VERSION);
        WaConfigSelector.accountsOverride = new List<WA_Account__mdt>{
            new WA_Account__mdt(WABA_Id__c = WABA_SECOND, Display_Label__c = 'AU Admissions (+91 90000 00002)', Active__c = true, Sort_Order__c = 2),
            new WA_Account__mdt(WABA_Id__c = WABA_INACTIVE, Display_Label__c = 'Old Number (+91 90000 00003)', Active__c = false, Sort_Order__c = 0),
            new WA_Account__mdt(WABA_Id__c = WABA_ACTIVE, Display_Label__c = 'Ahmedabad University (+91 90000 00001)', Active__c = true, Sort_Order__c = 1)
        };
    }

    /**
     * @description Assigns the Site guest permission set to the running user, so code that runs in user mode
     *              (the WA_Template_Log__c insert) gets exactly the guest user's access. Call before
     *              System.runAs(new User(Id = UserInfo.getUserId())) so the setup DML is separated from the test DML.
     */
    public static void grantGuestPermissionSet() {
        PermissionSet guest = [SELECT Id FROM PermissionSet WHERE Name = 'WA_TEMPLATE_MANAGER_GUEST' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = guest.Id);
    }

    /**
     * @description Sets RestContext for a call with the admin key.
     * @param method GET or POST
     * @param params query parameters
     * @param body request body, may be null
     * @return the request
     */
    public static RestRequest request(String method, Map<String, String> params, Blob body) {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/wa-template-api';
        request.httpMethod = method;
        request.addHeader(WaAuthService.HEADER_ADMIN_KEY, ADMIN_KEY);
        for (String key : params.keySet()) {
            request.addParameter(key, params.get(key));
        }
        request.requestBody = body;
        RestContext.request = request;
        RestContext.response = new RestResponse();
        return request;
    }

    /**
     * @description Parses the JSON written to RestContext.response.
     * @return response body as a map
     */
    public static Map<String, Object> responseBody() {
        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }

    /**
     * @description A valid Marketing template request covering every standard component.
     * @return JSON string
     */
    public static String marketingTemplateJson() {
        return '{"name":"admission_open_2027","language":"en_US","category":"MARKETING","components":['
            + '{"type":"HEADER","format":"TEXT","text":"Hello {{1}}","example":{"header_text":["Asha"]}},'
            + '{"type":"BODY","text":"Hi {{1}}, applications for {{2}} are open. Apply today.","example":{"body_text":[["Asha","B.Tech"]]}},'
            + '{"type":"FOOTER","text":"Ahmedabad University"},'
            + '{"type":"BUTTONS","buttons":['
            + '{"type":"QUICK_REPLY","text":"Interested"},'
            + '{"type":"QUICK_REPLY","text":"Not now"},'
            + '{"type":"URL","text":"Apply now","url":"https://ahduni.edu.in/apply/{{1}}","example":["https://ahduni.edu.in/apply/btech"]},'
            + '{"type":"PHONE_NUMBER","text":"Call us","phone_number":"+917900000000"},'
            + '{"type":"COPY_CODE","example":"AU2027"}'
            + ']}]}';
    }

    /**
     * @description A Meta list page.
     * @param startIndex first template number
     * @param count number of templates
     * @param afterCursor cursor to return, or null for the last page
     * @return JSON string
     */
    public static String templatePage(Integer startIndex, Integer count, String afterCursor) {
        List<Object> data = new List<Object>();
        for (Integer i = startIndex; i < startIndex + count; i++) {
            data.add(new Map<String, Object>{
                'id' => String.valueOf(1000 + i),
                'name' => 'template_' + i,
                'status' => 'APPROVED',
                'category' => 'MARKETING',
                'language' => 'en_US',
                'components' => new List<Object>{ new Map<String, Object>{ 'type' => 'BODY', 'text' => 'Hello there' } },
                'quality_score' => new Map<String, Object>{ 'score' => 'GREEN' }
            });
        }
        Map<String, Object> page = new Map<String, Object>{ 'data' => data };
        if (afterCursor != null) {
            page.put('paging', new Map<String, Object>{
                'cursors' => new Map<String, Object>{ 'before' => 'BEFORE', 'after' => afterCursor },
                'next' => 'https://graph.facebook.com/v27.0/x/message_templates?access_token=SHOULD_NOT_BE_FOLLOWED&after=' + afterCursor
            });
        } else {
            page.put('paging', new Map<String, Object>{ 'cursors' => new Map<String, Object>{ 'before' => 'BEFORE', 'after' => 'LAST' } });
        }
        return JSON.serialize(page);
    }
}