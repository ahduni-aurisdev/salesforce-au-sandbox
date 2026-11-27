/**
 * @description REST API behind the WhatsApp Template Manager page, served on the same public Site
 *              (…/services/apexrest/wa-template-api), so the page needs no CORS.
 *              GET  ?action=wabas                    active accounts from WA_Account__mdt
 *              GET  ?action=list&wabaId=             all templates of one WABA
 *              POST ?action=create&wabaId=           create a template (JSON body)
 *              POST ?action=upload&fileName=&fileType=   raw file body -> header_handle
 *              Every call needs the X-Admin-Key header and the feature flag WA_Template_Manager on.
 *              Response: {"ok":true,...} or {"ok":false,"error":"..."} with a matching HTTP status.
 *              Delete is out of scope by user decision (2026-11-26).
 * @author AU Development Team
 * @date 2026-11-26
 * @version 1.0
 * @lastModified 2026-11-26
 */
@RestResource(urlMapping='/wa-template-api')
global with sharing class WaTemplateApi {
    @TestVisible
    private static final String ACTION_WABAS = 'wabas';
    @TestVisible
    private static final String ACTION_LIST = 'list';
    @TestVisible
    private static final String ACTION_CREATE = 'create';
    @TestVisible
    private static final String ACTION_UPLOAD = 'upload';
    private static final Set<String> GET_ACTIONS = new Set<String>{ ACTION_WABAS, ACTION_LIST };
    private static final Set<String> POST_ACTIONS = new Set<String>{ ACTION_CREATE, ACTION_UPLOAD };
    private static final String METHOD_GET = 'GET';
    private static final String METHOD_POST = 'POST';
    private static final String PARAM_ACTION = 'action';
    private static final String PARAM_WABA_ID = 'wabaId';
    private static final String PARAM_FILE_NAME = 'fileName';
    private static final String PARAM_FILE_TYPE = 'fileType';
    private static final String LOG_NAME = 'WaTemplateManager';
    private static final String CLASS_NAME = 'WaTemplateApi';
    @TestVisible
    private static final String MSG_UNEXPECTED = 'Something went wrong in Salesforce. Try again; if it keeps happening, ask your Salesforce admin to check API Log.';

    @HttpGet
    global static void handleGet() {
        handle(METHOD_GET);
    }

    @HttpPost
    global static void handlePost() {
        handle(METHOD_POST);
    }

    private static void handle(String method) {
        RestRequest request = RestContext.request;
        String action = request == null || request.params == null ? null : request.params.get(PARAM_ACTION);
        Integer status = 200;
        Object payload;
        try {
            WaAuthService.authorize(request);
            payload = route(method, action, request);
        } catch (WaException apiError) {
            status = apiError.statusCode;
            payload = new WaTemplateModels.ErrorResponse(apiError.getMessage());
            if (apiError.logFailure) {
                ZoomLogger.logFailure(LOG_NAME, CLASS_NAME, action, apiError.getMessage(), apiError.detail);
            }
        } catch (Exception unexpected) {
            // Last-resort guard for a public endpoint: the user gets a safe message, the full error is logged.
            status = 500;
            payload = new WaTemplateModels.ErrorResponse(MSG_UNEXPECTED);
            ZoomLogger.logFailure(LOG_NAME, CLASS_NAME, action, unexpected);
        }
        writeResponse(status, payload);
    }

    private static Object route(String method, String action, RestRequest request) {
        String normalized = action == null ? '' : action.trim().toLowerCase();
        Boolean known = GET_ACTIONS.contains(normalized) || POST_ACTIONS.contains(normalized);
        if (!known) {
            throw WaException.of(400, 'Unknown action. Use one of: wabas, list, create, upload.');
        }
        Set<String> allowed = method == METHOD_GET ? GET_ACTIONS : POST_ACTIONS;
        if (!allowed.contains(normalized)) {
            throw WaException.of(405, 'Use ' + (method == METHOD_GET ? METHOD_POST : METHOD_GET) + ' for action ' + normalized + '.');
        }
        String wabaId = trimmed(request.params.get(PARAM_WABA_ID));
        if (normalized == ACTION_WABAS) {
            return WaTemplateService.listAccounts();
        }
        if (normalized == ACTION_LIST) {
            return WaTemplateService.listTemplates(wabaId);
        }
        if (normalized == ACTION_CREATE) {
            String body = request.requestBody == null ? null : request.requestBody.toString();
            return WaTemplateService.createTemplate(wabaId, body);
        }
        return WaTemplateService.uploadSample(request.requestBody, request.params.get(PARAM_FILE_NAME), request.params.get(PARAM_FILE_TYPE));
    }

    private static void writeResponse(Integer status, Object payload) {
        RestResponse response = RestContext.response;
        if (response == null) {
            return;
        }
        response.statusCode = status;
        response.addHeader('Content-Type', 'application/json;charset=UTF-8');
        response.addHeader('Cache-Control', 'no-store');
        response.addHeader('X-Content-Type-Options', 'nosniff');
        response.responseBody = Blob.valueOf(JSON.serialize(payload, true));
    }

    private static String trimmed(String value) {
        return value == null ? null : value.trim();
    }
}