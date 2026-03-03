@istest 
public class mCubeController_Test {
   
    @istest
    public static void inboundCalltest(){
         
   
        
        Lead lead = new Lead();
        lead.lastname = 'Test Lead';
        lead.Company = 'TestCompany';
        lead.Phone = '67878';
        lead.mobilePhone = '1111111'; 
        lead.Email = 'standarduser@testorgfil.com';
        insert lead;
        MCUBE_Object_Api__c  m  = new MCUBE_Object_Api__c ();
        m.name = 'lead';
        m.Field_to_Compare_Mobile_Incoming_Number__c = 'mobilePhone ';
        m.field__c = 'FirstName';
        m.field1__c = 'LastName';
        m.field2__c = 'company';
        m.Value__c = 'company';
        m.value1__c = 'company';
        m.value2__c = 'company';
        insert m;
         Profile p = [SELECT Id FROM Profile  limit 1];

        User u = new User(Alias = 'standt12', Email='standarduser@testorgfil.com',
                          EmailEncodingKey='UTF-8', LastName='Testing', LanguageLocaleKey='en_US',
                          LocaleSidKey='en_US', ProfileId = p.Id, 
                          TimeZoneSidKey='America/Los_Angeles', UserName='standarduser@testorg.com.123',MobilePhone = '111');
        u.massdialerIds__c = ','+lead.id;
        insert  u;
        
        string data = '{\"dialstatus\":\"CONNECTING\",\"endtime\":\"'+system.now()+'\",\"starttime\":\"'+system.now()+'\",\"empnumber\":\"111\",\"callfrom\":\"1111111\"}' ;        
        PageReference pageRef = Page.calland;
        Test.setCurrentPage(pageRef);
        ApexPages.currentPage().getParameters().put('data',data);
        mCubeController.inboundCall();
        
        
        data = '{\"dialstatus\":\"ANSWER\",\"endtime\":\"'+system.now()+'\",\"starttime\":\"'+system.now()+'\",\"empnumber\":\"111\",\"callfrom\":\"1111111\"}' ;        
        ApexPages.currentPage().getParameters().put('data',data);
        mCubeController.inboundCall();
        
        data = '{\"status\":\"ORIGINATE\",\"endtime\":\"'+system.now()+'\",\"starttime\":\"'+system.now()+'\",\"executive\":\"111\",\"customer\":\"1111111\",\"refid\":\"'+lead.id+'\"}' ;        
        ApexPages.currentPage().getParameters().put('data',data);
        mCubeController.inboundCall();
        
        data = '{\"dialstatus\":\"CALL COMPLETE\",\"endtime\":\"'+system.now()+'\",\"starttime\":\"'+system.now()+'\",\"executive\":\"111\",\"customer\":\"1111111\",\"refid\":\"'+lead.id+'\"}' ;        
        ApexPages.currentPage().getParameters().put('data',data);
        mCubeController.inboundCall();
       
                data = '{\"dialstatus\":\"CALL COMPLETE\",\"endtime\":\"'+system.now()+'\",\"starttime\":\"'+system.now()+'\",\"executive\":\"111\",\"customer\":\"1111111\"}' ;        
        ApexPages.currentPage().getParameters().put('data',data);
        mCubeController.inboundCall();
        mCubeController.readCall();
        
        mCubeController.readCall();

        
        System.runAs(u) {
            mCubeController.clickToCall(lead .id);
            mCubeController.clickToCallNumber(string.valueof( lead.id),'1111111' );
            mCubeController.readNumbers(string.valueof( lead.id) );
            pageRef = Page.Dialer;
            Test.setCurrentPage(pageRef);
            ApexPages.StandardSetController stdSetController = new ApexPages.StandardSetController(new List<lead>{lead});
            Dialercontroller s = new Dialercontroller(stdSetController );
            s.direct();
            u.massdialerIds__c = +','+lead.id;
            update u;
            
         }
        

        
    }
    
  }