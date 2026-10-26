@RestResource(urlMapping='/marketingcloud/whatsapp/*')
global without sharing class MarketingCloudWhatsAppWebhook {

    @HttpPost
    global static void receiveEvent() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        String requestBody = req.requestBody == null ? '' : req.requestBody.toString();

        System.debug(LoggingLevel.ERROR, '===== MARKETING CLOUD WHATSAPP EVENT =====');
        System.debug(LoggingLevel.ERROR, requestBody);
        System.debug(LoggingLevel.ERROR, '==========================================');

        // Always answer 200 so Marketing Cloud does not keep retrying; failures are logged.
        res.statusCode = 200;
        res.responseBody = Blob.valueOf('OK');
        // Marketing Cloud callback verification: echo the callbackId and verificationKey back.
        if (requestBody.contains('verificationKey')) {
            try {
                Map<String, Object> v = (Map<String, Object>) JSON.deserializeUntyped(requestBody);
                if (v.containsKey('verificationKey')) {
                    res.addHeader('Content-Type', 'application/json');
                    res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
                        'callbackId' => v.get('callbackId'), 'verificationKey' => v.get('verificationKey') }));
                    return;
                }
            } catch (Exception ignore) {
                // not a verification request; process normally
            }
        }
        try {
            WhatsAppEventService.process(requestBody);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'WhatsApp event processing failed: ' + e.getMessage() + ' ' + e.getStackTraceString());
            try {
                insert new WhatsApp_Message_Event__c(
                    Event_Key__c = EncodingUtil.convertToHex(Crypto.generateDigest('SHA1', Blob.valueOf(requestBody + String.valueOf(Datetime.now().getTime())))),
                    Processing_Status__c = 'Error',
                    Error__c = (e.getMessage() == null ? 'error' : e.getMessage()).left(255),
                    Raw_Payload__c = requestBody.left(131072));
            } catch (Exception ignore) {
                System.debug(LoggingLevel.ERROR, 'Could not store failed event: ' + ignore.getMessage());
            }
        }
    }
}