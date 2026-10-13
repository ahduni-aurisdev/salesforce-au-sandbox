global without sharing class mCubeController {
    
     
    @auraenabled
    webservice static List<string> readNumbers(String recordId) { 
        list<string> numbers = new list<string> ();
        string  mcubeObjectName = id.valueof( recordId).getSObjectType().getDescribe().getName() ;  
        List<MCUBE_Object_Api__c> mcubeObjectList =[select id,name,Field_to_Compare_Mobile_Incoming_Number__c from MCUBE_Object_Api__c where name =:mcubeObjectName ];
        string fieldsToquery = '';
        for(MCUBE_Object_Api__c m:  mcubeObjectList){
            fieldsToquery =  fieldsToquery+','+ m.Field_to_Compare_Mobile_Incoming_Number__c;
        }
        String condtn='Id='+'\''+recordId+'\'';
        String xQuery='Select id '+fieldsToquery+ ' from '+mcubeObjectName+' where '+condtn;
        system.debug(xQuery);         
        sObject so = Database.query(xQuery);
        for(MCUBE_Object_Api__c m:  mcubeObjectList){
            system.debug(m.Field_to_Compare_Mobile_Incoming_Number__c);
            system.debug((string)so.get(m.Field_to_Compare_Mobile_Incoming_Number__c));
            numbers.add((string)so.get(m.Field_to_Compare_Mobile_Incoming_Number__c));
        }
        system.debug(numbers);
        return numbers;
    
    }
    
    
    
    
    
    @auraenabled
    webservice static boolean clickToCallNumber(String recordId, String numberSelected) { 
        string  mcubeObjectName = id.valueof( recordId).getSObjectType().getDescribe().getName() ;  
        MCUBE_Object_Api__c mcubeObject=[select id,name,Field_to_Compare_Mobile_Incoming_Number__c,LandingNumber__c from MCUBE_Object_Api__c where name =:mcubeObjectName  limit 1];
        String condtn='Id='+'\''+recordId+'\'';
        String xQuery='Select id,'+mcubeObject.Field_to_Compare_Mobile_Incoming_Number__c+ ' from '+mcubeObjectName+' where '+condtn;
        system.debug(xQuery);         
        List<sObject> l = Database.query(xQuery);
        system.debug(l);        
        
        // Lead l =  [select id, Mobilephone from Lead where id=: leadId ];
        User u = [select mobilePhone from user where id=:userinfo.getUserId()];
        String m= numberSelected; 
        
        u.mobilePhone = u.mobilePhone.replace('+91','')  ; 
        u.mobilePhone = u.mobilePhone.replace('+','')  ;  
        u.mobilePhone=  u.mobilePhone.replaceAll('\\(', '');
        u.mobilePhone=  u.mobilePhone.replaceAll('\\)', '');
        u.mobilePhone=  u.mobilePhone.replaceAll(' ', '');
       	 //Number changes
        	  u.mobilePhone=  u.mobilePhone.right(10);

        if(m != null){
                m= m.replace('+91','')  ; 
                m=  m.replaceAll('\\(', '');
                m=  m.replaceAll('\\)', ''); 
                m=  m.replaceAll(' ', ''); 
            //Number Changes
                 m = m.right(10);
        }
        
        
        
     
        Mcube__mdt api1 =  [select Value__c from Mcube__mdt where DeveloperName ='APIKey'];
        Mcube__mdt api2 =  [select Value__c from Mcube__mdt where DeveloperName ='callbackUrl'];
        //for new Products
        List<Mcube__mdt> verstionList = [select Value__c from Mcube__mdt where DeveloperName ='Version'];

        Http http = new Http();
        HttpRequest request = new HttpRequest();
        
        string url = '';
        //For New Products 
         if(!(verstionList.isEmpty()) && verstionList[0].Value__c == '2'){
               //Mcube__mdt gsmConfig =   [select Value__c from Mcube__mdt where DeveloperName ='gsm'];
          // url  =   'http://api.mcube.com/Restmcube-api/outbound-calls?exenumber='+u.mobilePhone+'&custnumber='+m+'&refid='+l[0].get('Id')+'&refurl='+api2.Value__c +'/calland?refid='+l[0].get('Id')+'&gsm_config='+gsmConfig.Value__c;
           url  =   'http://api.mcube.com/Restmcube-api/outbound-calls';
             String token = api1.Value__c;
           request.setHeader('Content-Type', 'multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW');
           request.setHeader('Authorization', 'Bearer '+token );
           String boundary = '------WebKitFormBoundary7MA4YWxkTrZu0gW';
		   String requestBody = '';
             
             

           // Add your form data
			requestBody += boundary + '\r\n';
			requestBody += 'Content-Disposition: form-data; name="exenumber"\r\n\r\n';
			//requestBody += '8767316316\r\n';  
             requestBody += u.mobilePhone+'\r\n';
          
             // Add your form data
			requestBody += boundary + '\r\n';
			requestBody += 'Content-Disposition: form-data; name="custnumber"\r\n\r\n';
			requestBody += m+'\r\n';  
              
             // Add your form data
			requestBody += boundary + '\r\n';
			requestBody += 'Content-Disposition: form-data; name="refid"\r\n\r\n';
			requestBody += l[0].get('Id')+'\r\n';  
             
             // Add your form data
			requestBody += boundary + '\r\n';
			requestBody += 'Content-Disposition: form-data; name="refurl"\r\n\r\n';
			requestBody += +'1\r\n';  
            // Add closing boundary
			requestBody += boundary + '--\r\n';
             
            // Set the request body as a Blob
			request.setBody(requestBody); 
            
             System.debug(requestBody);
         }else{
           url  =   'http://mcube.vmc.in/api/outboundcall?apikey='+api1.Value__c  +'&exenumber='+u.mobilePhone+'&custnumber='+m+'&refid='+l[0].get('Id')+'&url='+api2.Value__c +'/calland?refid='+l[0].get('Id');
         }
        
        request.setEndpoint(url);
        request.setMethod('POST');
        system.debug(url);
        if(!test.isRunningTest()){
            HttpResponse response = http.send(request);
            String var= response.getBody() ;
            Map<String,String> responseMap = (Map<String, String>) JSON.deserialize(var, Map<String, String>.class); 
            system.debug(var);  
            system.debug('Status COde'+response.getStatusCode()); 
            if(response.getStatusCode() == 200 ){
            String bodyStatus =  responseMap.get('status');
        
                if(bodyStatus=='false')
                    throw  new AuraHandledException(responseMap.get('msg'));
                
              return true;
            }
          
            return false;
        }
       
        return false;
        
    }
    
    
    
    
    
    
    
    
    @auraenabled
    webservice static boolean clickToCall(String recordId) { 
       
        string  mcubeObjectName = id.valueof( recordId).getSObjectType().getDescribe().getName() ;  
        MCUBE_Object_Api__c mcubeObject=[select id,name,Campaign_Field_API__c, Source_Field_API__c, Field_to_Compare_Mobile_Incoming_Number__c,LandingNumber__c from MCUBE_Object_Api__c where name =:mcubeObjectName  limit 1];
        String condtn='Id='+'\''+recordId+'\'';
        String xQuery='Select id,'+mcubeObject.Field_to_Compare_Mobile_Incoming_Number__c+ ' from '+mcubeObjectName+' where '+condtn;
       
        
        system.debug(xQuery);         
        List<sObject> l = Database.query(xQuery);
        system.debug(l);        
        
        // Lead l =  [select id, Mobilephone from Lead where id=: leadId ];
        User u = [select mobilePhone from user where id=:userinfo.getUserId()];
        String m= String.valueof(l[0].get(mcubeObject.Field_to_Compare_Mobile_Incoming_Number__c));
        
        u.mobilePhone = u.mobilePhone.replace('+91','')  ; 
        u.mobilePhone = u.mobilePhone.replace('+','')  ;  
        u.mobilePhone=  u.mobilePhone.replaceAll('\\(', '');
        u.mobilePhone=  u.mobilePhone.replaceAll('\\)', '');
        u.mobilePhone=  u.mobilePhone.replaceAll(' ', '');
 		//Number changes
        	  u.mobilePhone=  u.mobilePhone.right(10);

        if(m != null){
                m= m.replace('+91','')  ; 
                m=  m.replaceAll('\\(', '');
                m=  m.replaceAll('\\)', ''); 
                m=  m.replaceAll(' ', ''); 
            //Number Changes
                 m = m.right(10);
        }
     
Mcube__mdt api1 =  [select Value__c from Mcube__mdt where DeveloperName ='APIKey'];
Mcube__mdt api2 =  [select Value__c from Mcube__mdt where DeveloperName ='callbackUrl'];
//for new Products
List<Mcube__mdt> verstionList = [select Value__c from Mcube__mdt where DeveloperName ='Version'];

Http http = new Http();
HttpRequest request = new HttpRequest();

string url = '';
//For New Products 
 if(!(verstionList.isEmpty()) && verstionList[0].Value__c == '2'){
      // Mcube__mdt gsmConfig =   [select Value__c from Mcube__mdt where DeveloperName ='gsm'];
  // url  =   'http://api.mcube.com/Restmcube-api/outbound-calls?exenumber='+u.mobilePhone+'&custnumber='+m+'&refid='+l[0].get('Id')+'&refurl='+api2.Value__c +'/calland?refid='+l[0].get('Id')+'&gsm_config='+gsmConfig.Value__c;
   url  =   'http://api.mcube.com/Restmcube-api/outbound-calls';
     String token = api1.Value__c ;
   request.setHeader('Content-Type', 'multipart/form-data; boundary=----WebKitFormBoundary7MA4YWxkTrZu0gW');
   request.setHeader('Authorization', 'Bearer '+token );
   String boundary = '------WebKitFormBoundary7MA4YWxkTrZu0gW';
   String requestBody = '';
     
     

   // Add your form data
    requestBody += boundary + '\r\n';
    requestBody += 'Content-Disposition: form-data; name="exenumber"\r\n\r\n';
    //requestBody += '8767316316\r\n';  
     requestBody += u.mobilePhone+'\r\n';
  
     // Add your form data
    requestBody += boundary + '\r\n';
    requestBody += 'Content-Disposition: form-data; name="custnumber"\r\n\r\n';
    requestBody += m+'\r\n';  
      
     // Add your form data
    requestBody += boundary + '\r\n';
    requestBody += 'Content-Disposition: form-data; name="refid"\r\n\r\n';
    requestBody += l[0].get('Id')+'\r\n';  
     
     // Add your form data
    requestBody += boundary + '\r\n';
    requestBody += 'Content-Disposition: form-data; name="refurl"\r\n\r\n';
    requestBody += +'1\r\n';  
    // Add closing boundary
    requestBody += boundary + '--\r\n';
     
    // Set the request body as a Blob
    request.setBody(requestBody); 
    
     System.debug(requestBody);
 }else{
   url  =   'http://mcube.vmc.in/api/outboundcall?apikey='+api1.Value__c  +'&exenumber='+u.mobilePhone+'&custnumber='+m+'&refid='+l[0].get('Id')+'&url='+api2.Value__c +'/calland?refid='+l[0].get('Id');
 }

request.setEndpoint(url);
request.setMethod('POST');
system.debug(url);
if(!test.isRunningTest()){
    HttpResponse response = http.send(request);
    String var= response.getBody() ;
    Map<String,String> responseMap = (Map<String, String>) JSON.deserialize(var, Map<String, String>.class); 
    system.debug(var);  
    system.debug('Status COde'+response.getStatusCode()); 
    if(response.getStatusCode() == 200 ){
    String bodyStatus =  responseMap.get('status');

        if(bodyStatus=='false')
            throw  new AuraHandledException(responseMap.get('msg'));
        
      return true;
    }
  
    return false;
}

return false;
        
    }
    
    public static void inboundCall(){ 
        String data = apexpages.currentpage().getparameters().get('data');
        List<MCUBE_Object_Api__c> mcubeObjectList =[select id,name,Campaign_Field_API__c, Source_Field_API__c,field__c,value__c,field1__c,value1__c,field2__c,value2__c, LandingNumber__c,  Field_to_Compare_Mobile_Incoming_Number__c from MCUBE_Object_Api__c order by  LandingNumber__c nulls first ];
        
        MCUBE_Object_Api__c  mcubeObject = new  MCUBE_Object_Api__c(); 
        if(mcubeObjectList.size() > 0 ){
        mcubeObject = mcubeObjectList[0];  
        string mobileNumber ='';
        if(data != null){ 
            data = EncodingUtil.urlDecode(data, 'UTF-8');            
            callWrapper cw = (callWrapper)JSON.deserialize(data,callWrapper.class); 
            List<Call_Detail__c> clist=[select id from Call_Detail__c where Call_ID__c =: cw.callid ];
            User u=new User();  
            for(MCUBE_Object_Api__c m: mcubeObjectList){
                if( m.LandingNumber__c == cw.landingnumber ){ 
                    mcubeObject = m;
                } 
            }
     if(   cw.executive == null){    
            if(cw.dialstatus  == 'CONNECTING'){   
                String xQuery='Select id from '+mcubeObject.Name+' where '+mcubeObject.Field_to_Compare_Mobile_Incoming_Number__c+'=\''+cw.callfrom+'\'';
                List<sObject> inboundList = Database.query(xQuery); 
                
                Call_Detail__c c = new Call_Detail__c(); 
                 
                List<user> usersList = [select id from user where mobilephone  like : cw.empnumber limit 1]; 
                if(usersList.size() > 0){
                      u = usersList[0]; 
                }
                
               
                c.Parent_ID__c=ApexPages.currentPage().getParameters().get('id');  
                u.LastAssignmentTime__c  = decimal.valueof(  system.now().gettime() );
                sObject l = Schema.getGlobalDescribe().get(mcubeObject.Name).newSObject() ;  
                if(inboundList.size() == 0){   
                    if(mcubeObject.field__c != null && mcubeObject.value__c != null){ 
                         L.put(mcubeObject.field__c, mcubeObject.value__c); 
                    } 
                    if(mcubeObject.field1__c != null && mcubeObject.value1__c != null){ 
                         L.put(mcubeObject.field1__c, mcubeObject.value1__c); 
                    }
                    if(mcubeObject.field2__c != null && mcubeObject.value2__c != null){ 
                         L.put(mcubeObject.field2__c, mcubeObject.value2__c); 
                    } 
                    l.put('OwnerId',u.id);   
                    l.put(mcubeObject.Field_to_Compare_Mobile_Incoming_Number__c,cw.callfrom); 
                   /* system.debug(mcubeObject); 
                    l.put(mcubeObject.Campaign_Field_API__c,cw.campaign); 
                    l.put(mcubeObject.Source_Field_API__c,cw.source );  */
                    insert l;   
                    c.Parent_ID__c = l.id;  
                    String url='/'+l.id+'/view';
                    c.Parent_URL__c=url;
                    c.Status__c=cw.dialstatus;      
                }else{ 
                    l = inboundList[0]; 
                    l.put('OwnerId',u.id);
                    update l;
                    c.Parent_ID__c  = l.id;
                }
                DateTime start = System.Now();
                if(cList.size() == 0){
                    c.Call_ID__c = cw.CallId;
                    c.Call_From__c = cw.callfrom;
                    c.Start_Time__c =   Datetime.valueof(cw.starttime).addHours(-5).addMinutes(-30); 
                    c.Call_ID__c = cw.callid;
                    c.Call_Type__c='Inbound Call'; 
                    c.Call_To__c=cw.empnumber;
                    c.Recording_File__c=cw.filename;
                    c.landing_number__c = cw.landingNumber;
                    c.Status__c=cw.dialstatus; 
                    if(mcubeObject.Name == 'Lead'){
                       c.lead__c =l.id;
                    } 
                    if(mcubeObject.Name == 'Account'){
                       c.Account__c =l.id;
                    } 
                    if(mcubeObject.Name == 'Contact'){
                       c.Contact__c = l.id;
                    }
                    if(mcubeObject.Name == 'Case'){
                       c.case__c = l.id;
                    }
                    insert c;
                } 
               sendNotification(cw.callfrom, l.id, u.id, mcubeObject.name);

            }else  
            {
                List<user> usersList = [select id from user where mobilephone  like : cw.empnumber limit 1]; 
                if(usersList.size() > 0){
                      u = usersList[0]; 
                }  
                String X1='\''+cw.callfrom+'\''; 
                String xQuery='Select id from '+mcubeObject.Name+' where '+mcubeObject.Field_to_Compare_Mobile_Incoming_Number__c+' ='+x1; 
                List<sObject> inboundList = Database.query(xQuery); 
                sObject l = inboundList[0];  
                if(cList.size() == 1){
                    Call_Detail__c  c = [select id from Call_Detail__c where Call_ID__c =: cw.callid ];
                    c.End_Time__c = Datetime.valueof(cw.endtime).addHours(-5).addMinutes(-30);
                    c.Status__c=cw.dialstatus;
                    c.Recording_File__c= cw.filename;
                    update c;
                }
            } 
      }
      if(cw.executive != null){ 
                
            if (    cw.status == 'ORIGINATE')
            {
                List<Call_Detail__c> cs=[select id from Call_Detail__c where Call_ID__c=:cw.CallId];
                String xcondn=mcubeObject.Field_to_Compare_Mobile_Incoming_Number__c+'=\''+cw.customer+'\'';
                String xQuery='Select id from '+mcubeObject.Name+' where '+xcondn;
                List<sObject> inboundList = Database.query(xQuery);
                
                Call_Detail__c c = new Call_Detail__c();  
                List<user> usersList = [select id from user where  mobilePhone like : cw.executive limit 1];  
                if(usersList.size() > 0){
                      u = usersList[0]; 
                } 
                c.Parent_ID__c = cw.refid;
                c.Parent_URL__c= '/'+ cw.refid+'/view';
                c.Status__c=cw.dialstatus; 
                DateTime start = System.Now();
                c.Call_ID__c = cw.CallId;
                c.Call_From__c =cw.executive ;
                c.Start_Time__c =   Datetime.valueof(cw.starttime).addHours(-5).addMinutes(-30); 
                c.Recording_File__c= cw.filename;
                c.Status__c=cw.status;
                c.Call_ID__c = cw.callid;
                c.Call_Type__c='Outbound Call';  
                c.Call_To__c=cw.customer;
                if(mcubeObject.Name == 'Lead'){
                   c.lead__c = cw.refid;
                } 
                if(mcubeObject.Name == 'Account'){
                   c.Account__c = cw.refid; 
                } 
                if(mcubeObject.Name == 'Contact'){
                   c.Contact__c = cw.refid;
                }
                if(mcubeObject.Name == 'Case'){
                   c.case__c = cw.refid;
                }
                insert c;
 
            }else   
            {                  
                if(cList.size() == 1){  
                    Call_Detail__c  c1 = [select id from Call_Detail__c where Call_ID__c =: cw.callid ];
                    c1.End_Time__c = Datetime.valueof(cw.endtime).addhours(-5).addMinutes(-30); 
                    c1.Status__c=cw.status;
                    c1.Recording_File__c= cw.filename;
                    update c1;
                }
            }
          }
        }   
       } 
            
    }
    
    public static void sendNotification(string mobile, string recordId,String userId, string objectName){
        
            CustomNotificationType notificationType = 
            [SELECT Id, DeveloperName 
             FROM CustomNotificationType 
             WHERE DeveloperName='Mcube_Notification']; 
                // Create a new custom notification
                Messaging.CustomNotification notification = new Messaging.CustomNotification(); 
                // Set the contents for the notification
                notification.setTitle('Incoming Call');
                notification.setBody('You Have a call on ' + system.now()); 
         
                // Set the notification type and target
                notification.setNotificationTypeId(notificationType.Id);
                notification.setTargetId(recordId);
               
                // Actually send the notification
                try {
                    notification.send(new set<string> {userId});
                }
                catch (Exception e) {
                    System.debug('Problem sending notification: ' + e.getMessage());
                }  
           
        
            List<CtiNotification__e> publishEvents = new List<CtiNotification__e>();
            CtiNotification__e eve = new CtiNotification__e();  
            eve.User_Id__c = userId;
            eve.Record_Id__c = recordId; 
            eve.ObjectName__c = objectName;
            publishEvents.add(eve);   
            if(!publishEvents.isEmpty()){
                EventBus.publish(publishEvents);
            }
    }
    
    public class  callWrapper{
        
        String refid;
        String  callid ;
        String callfrom; 
        string starttime ;
        String   filename; 
        String calid;
        string pulse;
        string source;
        String custfeedback;
        String exefeedback;
        String dialstatus;
        String callerbusiness;
        String callername;
        String remark;
        String calleraddress;
        String caller_email;
        String rate;
        string empnumber;
        string   endtime;
        String eid ;
        String empid;
        string gid;
        String empemail;
        String status;
        String executive;
        String customer;
        string LandingNumber;
        string campaign;
    }
   public   static string status{get;set;} 
   @auraEnabled
   public static  Call_Detail__c readCall(){ 
       try{
            datetime ss =  system.now().addSeconds(-10);
            Call_Detail__c c = [select Call_From__c,Call_ID__c,Call_To__c,Call_Type__c,End_Time__c,Executive_Contact_No__c,Parent_ID__c,Parent_URL__c,Recording_File__c,Start_Time__c,Status__c from Call_Detail__c where createddate >: ss and End_Time__c = null    order by createddate desc limit 1  ];
            return  c;    
       }catch(exception e){
           Call_Detail__c c = new Call_Detail__c();
            return  c;    
       }
                
    } 
    
    public  string recordIds= '';
   
   
   /*  
   @auraEnabled
   public static List<sobject> masdialinit(){
                 string userId =  userinfo.getUserId();
                 User   u = [select id,massdialerIds__c from User where id=:userId];  
                 string recordIdOrPrefix= '';
                 if( u.massdialerIds__c != null){
                    recordIdOrPrefix = u.massdialerIds__c.split(',')[1]; 
                 }
                 
                   String objectName = '';
                        try{
                            //Get prefix from record ID
                            //This assumes that you have passed at least 3 characters
                            String myIdPrefix = String.valueOf(recordIdOrPrefix).substring(0,3);
                             
                            //Get schema information
                            Map<String, Schema.SObjectType> gd =  Schema.getGlobalDescribe(); 
                             
                            //Loop through all the sObject types returned by Schema
                            for(Schema.SObjectType stype : gd.values()){ 
                 
                                Schema.DescribeSObjectResult r = stype.getDescribe();
                                String prefix = r.getKeyPrefix();
                                  
                                //Check if the prefix matches with requested prefix
                                if(prefix!=null && prefix.equals(myIdPrefix)){
                                    objectName = r.getName();
                                    System.debug('Object Name! ' + objectName);
                                    break;
                                }
                            }
                        }catch(Exception e){
                            System.debug(e);
                        }
                        List<id> idslist = u.massdialerIds__c.split(',');
                         List<sobject> llist = database.query('select id, name  from '+objectName +' where id in: idslist  ');
                         return  llist; 
    }  
    
    global static void callrouting(){
      RestResponse res = new RestResponse();
      RestContext.response.addHeader( 'Content-Type', 'application/json' );
      List<string> mobiles = new  List<string>();
      List<user> userslist = [select id,mobilephone from user where LastAssignmentTime__c != null order by LastAssignmentTime__c desc];
      for(user u: userslist ){
        mobiles.add(u.mobilephone ); 
      
      }      
      RestContext.response.responseBody = Blob.valueOf( SYSTEM.JSON.serialize( new Response( 'success', mobiles  ) ) );

    } 
    
    public class Response {
        public String status;
        public List<String> agentNumbers;
         
        public Response( String status, List<String> agentNumbers) {
            this.status     = status;
            this.agentNumbers = agentNumbers;
        }
        
    } 
   
    
    
    @AuraEnabled  
    public static  List<Call_Detail__c> callRecords(string recId){
        List<Call_Detail__c> callIds=[select id,Call_From__c,name, Call_to__c, Call_Type__c, End_Time__c, Start_Time__c, Status__c,Recording_File__c from Call_Detail__c where Parent_id__c=:recId order by createddate desc];
        
        return callIds;
    } */
    
}