@IsTest
private class WhatsAppTimelineControllerTest {
    @IsTest static void returnsMessagesForLeadAndContact() {
        Lead l = new Lead(LastName = 'T', Company = 'AU');
        insert l;
        Contact c = new Contact(LastName = 'C', MobilePhone = '9876543210');
        insert c;
        insert new List<WhatsApp_Message__c>{
            new WhatsApp_Message__c(Message_Key__c = 'a', Lead__c = l.Id, Status__c = 'Read'),
            new WhatsApp_Message__c(Message_Key__c = 'b', Contact__c = c.Id, Status__c = 'Sent') };
        System.assertEquals(1, WhatsAppTimelineController.getMessages(l.Id).size());
        System.assertEquals('Sent', WhatsAppTimelineController.getMessages(c.Id)[0].Status__c);
    }

    @IsTest static void accountAndOpportunityShowConvertedLeadAndContactMessages() {
        Account a = new Account(Name = 'Student Acc');
        insert a;
        Contact c = new Contact(LastName = 'C', MobilePhone = '9876543210', AccountId = a.Id);
        insert c;
        Opportunity o = new Opportunity(Name = 'Opp', AccountId = a.Id, StageName = 'Prospecting', CloseDate = Date.today());
        insert o;
        insert new WhatsApp_Message__c(Message_Key__c = 'x1', Contact__c = c.Id, Status__c = 'Delivered', Last_Event_At__c = Datetime.now());
        insert new WhatsApp_Message__c(Message_Key__c = 'x2', Contact__c = c.Id, Status__c = 'Read', Last_Event_At__c = Datetime.now().addMinutes(5));
        insert new WhatsApp_Message__c(Message_Key__c = 'x3', Status__c = 'Sent');
        List<WhatsApp_Message__c> forAccount = WhatsAppTimelineController.getMessages(a.Id);
        System.assertEquals(2, forAccount.size());
        System.assertEquals('Delivered', forAccount[0].Status__c, 'oldest first');
        System.assertEquals(2, WhatsAppTimelineController.getMessages(o.Id).size());
        Opportunity noAcc = new Opportunity(Name = 'NoAcc', StageName = 'Prospecting', CloseDate = Date.today());
        insert noAcc;
        System.assertEquals(0, WhatsAppTimelineController.getMessages(noAcc.Id).size());
    }

    @IsTest static void sameNumberOnTwoLeadsShowsAllMessages() {
        Lead a = new Lead(LastName = 'A', Company = 'AU', MobilePhone = '9876543210');
        Lead b = new Lead(LastName = 'B', Company = 'AU', MobilePhone = '+91 98765 43210');
        insert new List<Lead>{ a, b };
        insert new WhatsApp_Message__c(Message_Key__c = 'p1', Lead__c = a.Id, Phone_Key__c = '9876543210', Status__c = 'Read', Last_Event_At__c = Datetime.now());
        insert new WhatsApp_Message__c(Message_Key__c = 'p2', Lead__c = b.Id, Phone_Key__c = '9876543210', Status__c = 'Sent', Last_Event_At__c = Datetime.now().addMinutes(1));
        insert new WhatsApp_Message__c(Message_Key__c = 'p3', Phone_Key__c = '9000000000', Status__c = 'Sent');
        System.assertEquals(2, WhatsAppTimelineController.getMessages(a.Id).size());
        System.assertEquals(2, WhatsAppTimelineController.getMessages(b.Id).size());
        Account acc = new Account(Name = 'Acc', Phone = '98765 43210');
        insert acc;
        Opportunity o = new Opportunity(Name = 'Opp', AccountId = acc.Id, StageName = 'Prospecting', CloseDate = Date.today());
        insert o;
        System.assertEquals(2, WhatsAppTimelineController.getMessages(acc.Id).size());
        System.assertEquals(2, WhatsAppTimelineController.getMessages(o.Id).size());
    }
}