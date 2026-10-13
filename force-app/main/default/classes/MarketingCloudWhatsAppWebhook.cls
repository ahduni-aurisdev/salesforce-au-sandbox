@RestResource(urlMapping='/marketingcloud/whatsapp/*')
global without sharing class MarketingCloudWhatsAppWebhook {

    @HttpPost
    global static void receiveEvent() {

        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String requestBody = req.requestBody.toString();

        System.debug(LoggingLevel.ERROR,
            '===== MARKETING CLOUD WHATSAPP EVENT ====='
        );

        System.debug(LoggingLevel.ERROR, requestBody);

        System.debug(LoggingLevel.ERROR,
            '=========================================='
        );

        res.statusCode = 200;
        res.responseBody = Blob.valueOf('OK');
    }
}