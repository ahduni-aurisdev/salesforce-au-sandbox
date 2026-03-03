public class ZoomWebinarService {
    
    // Function to fetch all webinars and registrants, and update tracking sources
    // public void fetchAndUpdateWebinarRegistrants() {
    //     // Step 1: Fetch all webinars from Zoom API
    //     HttpRequest webinarReq = new HttpRequest();
    //     webinarReq.setEndpoint('https://api.zoom.us/v2/users/me/webinars');
    //     webinarReq.setMethod('GET');
    //     webinarReq.setHeader('Authorization', 'Bearer ' + 'eyJzdiI6IjAwMDAwMSIsImFsZyI6IkhTNTEyIiwidiI6IjIuMCIsImtpZCI6IjRiOTEwOTIxLTljODUtNGUyZS1iYjIxLTI1NGNjODYwODc0NyJ9.eyJ2ZXIiOjEwLCJhdWlkIjoiNTkzYThiZDJhNjFjM2MxYWVjZjJjMTM1ODY4YjU2YzQ0OTU3MTA3NzM0M2NhY2E0NDJhZjM5MGM1MTA4YjEyNyIsImNvZGUiOiJFWm5xUlB3eFhFbTZYQWZMRjlFUUN1TW1ORGRNSFk2T2ciLCJpc3MiOiJ6bTpjaWQ6eTVIU0xhc1RmQ0F5OTVNNXZ5MzlRIiwiZ25vIjowLCJ0eXBlIjowLCJ0aWQiOjAsImF1ZCI6Imh0dHBzOi8vb2F1dGguem9vbS51cyIsInVpZCI6InhXb3RRNllnUTY2MFhDQ0R6WHM2dUEiLCJuYmYiOjE3MzE0OTIwNDgsImV4cCI6MTczMTQ5NTY0OCwiaWF0IjoxNzMxNDkyMDQ4LCJhaWQiOiJvRkQ1UFVqQVNMMi1zbURwM2JfRlB3In0.PhR03YJfZyJwsBgrUn7hCHZWK51GNwfQFH_FuOls65Up8gDG-lFud3SqzUZHfREEbE83yq6bc3djhuKZbwcvqw');
        
    //     Http http = new Http();
    //     HttpResponse webinarRes = http.send(webinarReq);
        
    //     if (webinarRes.getStatusCode() == 200) {
    //         // Map<String, Object> webinarResponseMap = (Map<String, Object>) JSON.deserializeUntyped(webinarRes.getBody());
    //         // List<Map<String, Object>> webinars = (List<Map<String, Object>>) webinarResponseMap.get('webinars');

    //         // Deserialize the response into a Map that contains a 'webinars' list
    //         Map<String, Object> webinarResponseMap = (Map<String, Object>) JSON.deserializeUntyped(webinarRes.getBody());
    //         List<Map<String, Object>> webinars = (List<Map<String, Object>>) webinarResponseMap.get('webinars');

            
    //         // Step 2: Loop through each webinar and fetch registrants
    //         for (Map<String, Object> webinar : webinars) {
    //             String webinarId = (String) webinar.get('id');
    //             fetchAndUpdateRegistrantsForWebinar(webinarId);
    //         }
    //     } else {
    //         System.debug('Failed to fetch webinars: ' + webinarRes.getBody());
    //     }
    // }
    
    public void fetchAndUpdateWebinarRegistrants() {
        // Step 1: Fetch all webinars from Zoom API
        HttpRequest webinarReq = new HttpRequest();
        webinarReq.setEndpoint('https://api.zoom.us/v2/users/me/webinars');
        webinarReq.setMethod('GET');
        webinarReq.setHeader('Authorization', 'Bearer ' + 'eyJzdiI6IjAwMDAwMSIsImFsZyI6IkhTNTEyIiwidiI6IjIuMCIsImtpZCI6Ijg5MjNlYjk1LTY5ZTUtNGIxYS1iZjcwLTA5MTk4NTNmZmEzZCJ9.eyJ2ZXIiOjEwLCJhdWlkIjoiNTkzYThiZDJhNjFjM2MxYWVjZjJjMTM1ODY4YjU2YzQ0OTU3MTA3NzM0M2NhY2E0NDJhZjM5MGM1MTA4YjEyNyIsImNvZGUiOiJZcmNjb1ZPUUFzUlg1bVNHWWdfUzJpQ3JHZlM4UFlxUGciLCJpc3MiOiJ6bTpjaWQ6eTVIU0xhc1RmQ0F5OTVNNXZ5MzlRIiwiZ25vIjowLCJ0eXBlIjowLCJ0aWQiOjAsImF1ZCI6Imh0dHBzOi8vb2F1dGguem9vbS51cyIsInVpZCI6InhXb3RRNllnUTY2MFhDQ0R6WHM2dUEiLCJuYmYiOjE3MzE0OTMzNzYsImV4cCI6MTczMTQ5Njk3NiwiaWF0IjoxNzMxNDkzMzc2LCJhaWQiOiJvRkQ1UFVqQVNMMi1zbURwM2JfRlB3In0.T_XjxEwEpP2QvdMwQHZS45dzUlRhido4QmrDlsCwz4B_CUdfZT47icUx9dPBo3n8UsdPtvuYJ_7MT_20B63x_w');
        
        Http http = new Http();
        HttpResponse webinarRes = http.send(webinarReq);
        
        if (webinarRes.getStatusCode() == 200) {
            // Deserialize the JSON response into a map of String, Object
            Map<String, Object> webinarResponseMap = (Map<String, Object>) JSON.deserializeUntyped(webinarRes.getBody());
            
            // Fetch the list of webinars
            List<Object> webinarsRaw = (List<Object>) webinarResponseMap.get('webinars');
            
            // Step 2: Loop through each webinar and fetch registrants
            for (Object webinarObj : webinarsRaw) {
                Map<String, Object> webinar = (Map<String, Object>) webinarObj;
                
                // Safely cast the webinarId to String, ensure it handles Long types as well
                String webinarId = String.valueOf(webinar.get('id')); // Converting Long to String if necessary
                
                fetchAndUpdateRegistrantsForWebinar(webinarId);
            }
        } else {
            System.debug('Failed to fetch webinars: ' + webinarRes.getBody());
        }
    }
    
    // Step 3: Function to fetch registrants for a specific webinar and update Salesforce
    public void fetchAndUpdateRegistrantsForWebinar(String webinarId) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://api.zoom.us/v2/webinars/' + webinarId + '/registrants');
        req.setMethod('GET');
        req.setHeader('Authorization', 'Bearer ' + 'eyJzdiI6IjAwMDAwMSIsImFsZyI6IkhTNTEyIiwidiI6IjIuMCIsImtpZCI6Ijg5MjNlYjk1LTY5ZTUtNGIxYS1iZjcwLTA5MTk4NTNmZmEzZCJ9.eyJ2ZXIiOjEwLCJhdWlkIjoiNTkzYThiZDJhNjFjM2MxYWVjZjJjMTM1ODY4YjU2YzQ0OTU3MTA3NzM0M2NhY2E0NDJhZjM5MGM1MTA4YjEyNyIsImNvZGUiOiJZcmNjb1ZPUUFzUlg1bVNHWWdfUzJpQ3JHZlM4UFlxUGciLCJpc3MiOiJ6bTpjaWQ6eTVIU0xhc1RmQ0F5OTVNNXZ5MzlRIiwiZ25vIjowLCJ0eXBlIjowLCJ0aWQiOjAsImF1ZCI6Imh0dHBzOi8vb2F1dGguem9vbS51cyIsInVpZCI6InhXb3RRNllnUTY2MFhDQ0R6WHM2dUEiLCJuYmYiOjE3MzE0OTMzNzYsImV4cCI6MTczMTQ5Njk3NiwiaWF0IjoxNzMxNDkzMzc2LCJhaWQiOiJvRkQ1UFVqQVNMMi1zbURwM2JfRlB3In0.T_XjxEwEpP2QvdMwQHZS45dzUlRhido4QmrDlsCwz4B_CUdfZT47icUx9dPBo3n8UsdPtvuYJ_7MT_20B63x_w');
        
        Http http = new Http();
        HttpResponse res = http.send(req);
        
        if (res.getStatusCode() == 200) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            List<Map<String, Object>> registrants = (List<Map<String, Object>>) responseMap.get('registrants');
            
            Integer visitorCount = 0;
            
            // Step 4: Loop through each registrant and update Salesforce records
            for (Map<String, Object> registrant : registrants) {
                String email = (String) registrant.get('email');
                String trackingSource = (String) registrant.get('tracking_source');
                
                // Query for the Lead or Contact in Salesforce using the email
                List<Lead> leads = [SELECT Id, Webinar_Lead_Source__c FROM Lead WHERE Email = :email LIMIT 1];
                
                if (leads.size() > 0) {
                    Lead lead = leads[0];
                    // Update the tracking source
                    lead.Webinar_Lead_Source__c = trackingSource;
                    update lead;
                } else {
                    // You can add a similar query for Contact records if needed
                    // Optionally, create a new lead if no matching records are found
                }
                
                // Increment visitor count
                visitorCount++;
            }
            
            // Step 5: Optionally update visitor count for the webinar in Salesforce
            // Assuming you have a Webinar custom object or any related field to store visitor count
            ZVC__Zoom_Webinar_Link__c webinar = [SELECT Id, Visitor_Count__c FROM ZVC__Zoom_Webinar_Link__c WHERE 	ZVC__Zoom_Webinar__c = :webinarId LIMIT 1];
            if (webinar != null) {
                webinar.Visitor_Count__c = visitorCount;
                update webinar;
            }            
        } else {
            System.debug('Failed to fetch registrants for webinar: ' + webinarId + ' Error: ' + res.getBody());
        }
    }
}