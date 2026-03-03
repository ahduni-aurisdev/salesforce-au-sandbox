@RestResource(urlMapping='/zoomWebinars/*')
global with sharing class ZoomWebinarRestAPI {
    
    // Define a RESTful GET method to trigger fetching webinar registrants
    @HttpGet
    global static void fetchAndUpdateWebinars() {
        try {
            ZoomWebinarService zoomService = new ZoomWebinarService();
            zoomService.fetchAndUpdateWebinarRegistrants();
            RestContext.response.statusCode = 200;
            RestContext.response.responseBody = Blob.valueOf('Webinar registrants updated successfully');
        } catch (Exception e) {
            RestContext.response.statusCode = 500;
            RestContext.response.responseBody = Blob.valueOf('Error: ' + e.getMessage());
        }
    }
}