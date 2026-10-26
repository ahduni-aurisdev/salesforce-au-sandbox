/**
 * @description Versioned REST endpoint for bulk Task creation against Leads and Accounts.
 * @author AU Development Team
 * @date 2026-10-23
 * @version 1.0
 * @lastModified 2026-10-23
 */
@RestResource(urlMapping='/v1/activities/tasks')
global with sharing class TaskActivityRestResource {
    private static final String CONTENT_TYPE = 'application/json';

    @HttpPost
    global static void createTasks() {
        RestRequest request = RestContext.request;
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', CONTENT_TYPE);
        String requestId = createRequestId();

        try {
            if (request == null || request.requestBody == null || request.requestBody.size() == 0) {
                throw new TaskActivityService.TaskActivityApiException('Request body is required.');
            }
            TaskActivityApiModels.RequestEnvelope requestEnvelope =
                (TaskActivityApiModels.RequestEnvelope) JSON.deserialize(
                    request.requestBody.toString(),
                    TaskActivityApiModels.RequestEnvelope.class
                );
            TaskActivityApiModels.ResponseEnvelope responseEnvelope =
                TaskActivityService.process(requestEnvelope, requestId);
            response.statusCode = responseEnvelope.success ? 200 : 207;
            response.responseBody = Blob.valueOf(JSON.serialize(responseEnvelope));
        } catch (System.JSONException exceptionValue) {
            writeError(response, 400, requestId, 'Invalid JSON payload: ' + exceptionValue.getMessage());
        } catch (TaskActivityService.TaskActivityApiException exceptionValue) {
            writeError(response, 400, requestId, exceptionValue.getMessage());
        } catch (Exception exceptionValue) {
            String errorMessage = exceptionValue.getMessage();
            TaskActivityService.logUnexpectedFailure(requestId, errorMessage);
            writeError(response, 500, requestId, errorMessage);
        }
    }

    private static void writeError(
        RestResponse response,
        Integer statusCode,
        String requestId,
        String message
    ) {
        TaskActivityApiModels.ResponseEnvelope responseEnvelope = new TaskActivityApiModels.ResponseEnvelope();
        responseEnvelope.requestId = requestId;
        responseEnvelope.success = false;
        responseEnvelope.totalRecords = 0;
        responseEnvelope.successCount = 0;
        responseEnvelope.failureCount = 1;
        TaskActivityApiModels.RecordResult result = new TaskActivityApiModels.RecordResult();
        result.index = -1;
        result.action = 'FAILED';
        result.success = false;
        result.errors.add(message);
        responseEnvelope.results.add(result);
        response.statusCode = statusCode;
        response.responseBody = Blob.valueOf(JSON.serialize(responseEnvelope));
    }

    private static String createRequestId() {
        return 'TA-' + Datetime.now().formatGMT('yyyyMMddHHmmssSSS') + '-' +
            EncodingUtil.convertToHex(Crypto.generateAesKey(128)).substring(0, 8);
    }
}