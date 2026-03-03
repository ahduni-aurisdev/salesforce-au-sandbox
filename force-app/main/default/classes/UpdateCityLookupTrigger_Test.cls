@isTest
public class UpdateCityLookupTrigger_Test {
	 public static testmethod void Testmeth1(){
         
        List<User> userList = new List<User>();
        User u1 = new User(
            Alias = 'testu', Email = 'test@akshareducation.com', EmailEncodingKey = 'UTF-8', LastName = 'Test1', LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US', TimeZoneSidKey='America/Los_Angeles', ProfileId = [Select Id from Profile where Name = 'System Administrator'].Id,
            UserName='test1@akshareducation.com'
        );
        userList.add(u1);
         
        User u2 = new User(
            Alias = 'testu', Email = 'test@akshareducation.com', EmailEncodingKey = 'UTF-8', LastName = 'Test2', LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US', TimeZoneSidKey='America/Los_Angeles', ProfileId = [Select Id from Profile where Name = 'System Administrator'].Id,
            UserName='test2@akshareducation.com'
        );
        userList.add(u2);
        INSERT userList;
         
         List<State__c> stateList = new  List<State__c>();
         State__c st = new State__c();
         st.Name = 'TamilNadu';
         stateList.add(st);
         
         State__c st2 = new State__c();
         st2.Name = 'Gujarat';
         stateList.add(st2);
         INSERT stateList;
         
         List<Round_Robin_User__c> rruserList = new  List<Round_Robin_User__c>();
         Round_Robin_User__c rs = new Round_Robin_User__c();
         rs.State__c = st.Id;
         rs.Sequence_Number__c = 1;
         rs.User__c = u1.Id;
         rs.Record_Last_Added__c = false;
         rs.Active__c = true;
         rruserList.add(rs);
         
         Round_Robin_User__c rs2 = new Round_Robin_User__c();
         rs2.State__c = st2.Id;
         rs2.Sequence_Number__c = 2;
         rs2.User__c = u2.Id;
         rs2.Record_Last_Added__c = false;
         rs2.Active__c = true;
         rruserList.add(rs2);
         INSERT rruserList;
         
         List<Lead> LeadList = new List<Lead>();
         Lead ld = new lead();
         ld.LastName = 'Sam Anderson';
         ld.Email = 'vijai.dhamu@gmail.com';
         ld.State_Union_Territory_Province__c = st.Id;
         LeadList.add(ld);
         
         Lead ld2 = new lead();
         ld2.LastName = 'Ram Tennyson';
         ld2.Email = 'vijai2.dhamu@gmail.com';
         ld2.School_State__c = st2.Id;
         LeadList.add(ld2);
         INSERT LeadList;
    
     }
}