@isTest
public class RoundrobinUserTrigger_Test {
    
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
        
        State__c st = new State__c();
        st.Name = 'TamilNadu';
        INSERT st;
        
        List<Round_Robin_User__c> rruserList = new  List<Round_Robin_User__c>();
        Round_Robin_User__c rs = new Round_Robin_User__c();
        rs.State__c = st.Id;
        rs.Sequence_Number__c = 1;
        rs.User__c = u1.Id;
        rs.Record_Last_Added__c = true;
        rs.Active__c = true;
        rruserList.add(rs);
        
        Round_Robin_User__c rs2 = new Round_Robin_User__c();
        rs2.State__c = st.Id;
        rs2.Sequence_Number__c = 2;
        rs2.User__c = u2.Id;
        rs2.Record_Last_Added__c = false;
        rs2.Active__c = true;
        rruserList.add(rs2);
        INSERT rruserList;
        
        rs2.Record_Last_Added__c = true;
        UPDATE rs2;
   
    }
}