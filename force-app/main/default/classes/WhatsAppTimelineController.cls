public with sharing class WhatsAppTimelineController {

    private static final String FIELDS = 'Id, Name, Direction__c, Status__c, Template_Name__c, Journey_Name__c, Campaign_Name__c, Message_Text__c, '
        + 'Sent_At__c, Delivered_At__c, Read_At__c, Failed_At__c, Failure_Reason__c, Last_Event_At__c, Phone__c, Sender_Number__c, '
        + 'Message_Type__c, Attachment_Name__c, Media_Mime_Type__c, Received_At__c, Lead__c, Lead__r.Name, Contact__c, Contact__r.Name';

    /**
     * Conversation for a Lead, Contact, Account or Opportunity, oldest first.
     * It contains every message sent to the phone number(s) on the record, plus the messages linked to the record itself
     * (for an Account / Opportunity: its Contacts and the Leads converted into the Account).
     */
    @AuraEnabled(cacheable=true)
    public static List<WhatsApp_Message__c> getMessages(Id recordId) {
        SObjectType t = recordId.getSObjectType();
        Set<String> keys = new Set<String>();
        String linkCond;
        Id target = recordId;

        if (t == Contact.SObjectType) {
            for (Contact c : [SELECT MobilePhone, Phone FROM Contact WHERE Id = :recordId]) {
                addKeys(keys, new List<String>{ c.MobilePhone, c.Phone });
            }
            linkCond = 'Contact__c = :target';
        } else if (t == Account.SObjectType) {
            for (Account a : [SELECT Phone, PersonMobilePhone FROM Account WHERE Id = :recordId]) {
                addKeys(keys, new List<String>{ a.Phone, a.PersonMobilePhone });
            }
            linkCond = 'Lead__r.ConvertedAccountId = :target OR Contact__r.AccountId = :target';
        } else if (t == Opportunity.SObjectType) {
            for (Opportunity o : [SELECT AccountId, Phone__c, Account.Phone, Account.PersonMobilePhone FROM Opportunity WHERE Id = :recordId]) {
                addKeys(keys, new List<String>{ o.Phone__c, o.Account.Phone, o.Account.PersonMobilePhone });
                target = o.AccountId;
            }
            linkCond = 'Lead__r.ConvertedAccountId = :target OR Contact__r.AccountId = :target';
        } else {
            for (Lead l : [SELECT Phone, MobilePhone, Whatsapp_Number__c, MC_Phone_Number__c FROM Lead WHERE Id = :recordId]) {
                addKeys(keys, new List<String>{
                    l.Phone, l.MobilePhone, l.Whatsapp_Number__c, l.MC_Phone_Number__c == null ? null : l.MC_Phone_Number__c.toPlainString() });
            }
            linkCond = 'Lead__c = :target';
        }

        if (target == null) {
            linkCond = 'Id = null'; // e.g. an Opportunity without an Account: never match "ConvertedAccountId = null"
        }
        String cond = linkCond;
        if (!keys.isEmpty()) {
            cond = '(' + linkCond + ') OR Phone_Key__c IN :keys';
        }
        List<WhatsApp_Message__c> rows = Database.query(
            'SELECT ' + FIELDS + ' FROM WhatsApp_Message__c WHERE ' + cond + ' ORDER BY Last_Event_At__c DESC NULLS LAST LIMIT 200');
        List<WhatsApp_Message__c> ordered = new List<WhatsApp_Message__c>();
        for (Integer i = rows.size() - 1; i >= 0; i--) {
            ordered.add(rows[i]);
            System.debug(rows[i]);
        }
        return ordered;
    }

    private static void addKeys(Set<String> keys, List<String> phones) {
        for (String p : phones) {
            String k = WhatsAppEventService.last10(p);
            if (k != null) {
                keys.add(k);
            }
        }
    }
}