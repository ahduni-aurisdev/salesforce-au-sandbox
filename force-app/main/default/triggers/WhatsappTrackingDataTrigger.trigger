trigger WhatsappTrackingDataTrigger on Whatsapp_tracking_data__c (after insert) {
    // Map to store Whatsapp_Summary__c based on Template_Name__c and Lead__c combination
    Map<String, Whatsapp_Summary__c> existingSummaryMap = new Map<String, Whatsapp_Summary__c>();
    
    // Collect unique combinations of Template_Name__c and Lead__c from inserted records
    Set<String> uniqueCombinations = new Set<String>();
    
    Set<String> processedTrackingDataKeys = new Set<String>();
    for (Whatsapp_Summary__c existingsummarydata : [select id,unique_combination__c from Whatsapp_Summary__c] ){
        processedTrackingDataKeys.add(existingsummarydata.unique_combination__c);
    }
    
    Map<String,Whatsapp_Summary__c> whatsappSummaryMap = new  Map<String,Whatsapp_Summary__c>();
    for (Whatsapp_tracking_data__c trackingRecord : Trigger.New) {
        String key = trackingRecord.Template_Name__c + trackingRecord.Lead__c;
        if (trackingRecord.Template_Name__c != null && trackingRecord.Lead__c != null && !processedTrackingDataKeys.contains(key)) {
            Whatsapp_Summary__c ws = new Whatsapp_Summary__c();
            ws.Name = trackingRecord.Template_Name__c;
            ws.Template_Name__c = trackingRecord.Template_Name__c;
            ws.Lead__c = trackingRecord.Lead__c;
            ws.Name = trackingRecord.Template_Name__c;
            ws.Template_Name__c = trackingRecord.Template_Name__c;
            ws.Lead__c = trackingRecord.Lead__c;
            if (trackingRecord.Whatsapp_status__c == 'Read') {
                ws.Read__c = true;
                ws.Read_Date_and_Time__c = trackingRecord.Message_Data_and_time__c;
            } else if (trackingRecord.Whatsapp_status__c == 'Sent') {
                ws.Sent__c = true;
                ws.Sent_Date_and_Time__c  = trackingRecord.Message_Data_and_time__c;
            } else if (trackingRecord.Whatsapp_status__c == 'Delivered') {
                ws.Delivered__c = true;
                ws.Delivered_Date_and_Time__c  = trackingRecord.Message_Data_and_time__c;
            } else if (trackingRecord.Whatsapp_status__c == 'Failed') {
                ws.Failed__c = true;
                ws.Failed_Date_and_Time__c  = trackingRecord.Message_Data_and_time__c;
                ws.Failed_reason__c = trackingRecord.Reason__c;
            }
            whatsappSummaryMap.put(key,ws);
        }
        uniqueCombinations.add(key);
    }
    if (!whatsappSummaryMap.isEmpty()) {
        insert whatsappSummaryMap.values();
    }
    
    
    SYstem.debug('uniqueCombinations::'+uniqueCombinations);
    // Query existing Whatsapp_Summary__c records for the collected combinations
    if (!uniqueCombinations.isEmpty()) {
        for (Whatsapp_Summary__c summary : [
            SELECT Id, Template_Name__c, Lead__c, Read__c, Sent__c, Delivered__c, Failed__c,unique_combination__c
            FROM Whatsapp_Summary__c
            WHERE unique_combination__c IN: uniqueCombinations
        ]) {
            String key = summary.Template_Name__c + summary.Lead__c;
            existingSummaryMap.put(key, summary);
        }
    }
    
    
    // List to hold new and updated Whatsapp_Summary__c records
    List<Whatsapp_Summary__c> summaryRecordsToUpdate = new List<Whatsapp_Summary__c>();
    List<Whatsapp_Summary__c> summaryRecordsToInsert = new List<Whatsapp_Summary__c>();
    System.debug('existingSummaryMap::'+existingSummaryMap);
    // Process each inserted record
    for (Whatsapp_tracking_data__c trackingRecord : Trigger.New) {
        if (trackingRecord.Template_Name__c != null && trackingRecord.Lead__c != null) {
            String key = trackingRecord.Template_Name__c  + trackingRecord.Lead__c;
            Whatsapp_Summary__c summary;
            System.debug('key::'+key);
            // Check if the summary record already exists
            if (existingSummaryMap.containsKey(key)) {
                summary = existingSummaryMap.get(key);
                // Update counts based on Whatsapp_status__c
                if (trackingRecord.Whatsapp_status__c == 'Read') {
                    summary.Read__c = true;
                    summary.Read_Date_and_Time__c = trackingRecord.Message_Data_and_time__c;
                } else if (trackingRecord.Whatsapp_status__c == 'Sent') {
                    summary.Sent__c = true;
                    summary.Sent_Date_and_Time__c  = trackingRecord.Message_Data_and_time__c;
                } else if (trackingRecord.Whatsapp_status__c == 'Delivered') {
                    summary.Delivered__c = true;
                    summary.Delivered_Date_and_Time__c  = trackingRecord.Message_Data_and_time__c;
                } else if (trackingRecord.Whatsapp_status__c == 'Failed') {
                    summary.Failed__c = true;
                    summary.Failed_Date_and_Time__c  = trackingRecord.Message_Data_and_time__c;
                	summary.Failed_reason__c = trackingRecord.Reason__c;
                }
                System.debug('summary::'+summary);
                existingSummaryMap.put(key, summary);
               
            } 
        }
    }
   
    System.debug('summaryRecordsToUpdate::'+summaryRecordsToUpdate);
    // Upsert the Whatsapp_Summary__c records
    if (!existingSummaryMap.isempty()) {
        update existingSummaryMap.values();
    }
}