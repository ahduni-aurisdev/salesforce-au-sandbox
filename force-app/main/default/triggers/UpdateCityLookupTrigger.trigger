trigger UpdateCityLookupTrigger on Lead (before insert, before update) {
    
    if (Trigger.isBefore) {
        
        //if (Trigger.isInsert) {
        
        List<City__c> cityList = new List<City__c>();
        List<State__c> stateList = new List<State__c>();
        List<Country__c> countryList = new List<Country__c>();
        Set<String> cityNameSet = new Set<String>();
        Set<String> stateNameSet = new Set<String>();
        Set<String> countryNameSet = new Set<String>();
        Set<Id> stateId = new  Set<Id>();
        
        for (Lead lObj : Trigger.new) {
            cityNameSet.add(lObj.City);
            stateNameSet.add(lObj.State);
            countryNameSet.add(lObj.Country);
        }
        
        cityList = [
            SELECT Id, Name
            FROM City__c
            WHERE Name IN: cityNameSet
        ];
        stateList = [
            SELECT Id, Name
            FROM State__c
            WHERE Name IN: stateNameSet
        ];
        countryList = [
            SELECT Id, Name
            FROM Country__c
            WHERE Name IN: countryNameSet
        ];
        
        for (Lead lObj : Trigger.new) {
            for (City__c city : cityList) {
                System.debug('Trigger City :>> ' +city);
                if (city.Name == lObj.City) {
                    lObj.City_Town_Village__c = city.Id;
                }
            }
            for (State__c state : stateList) {
                if (state.Name == lObj.State) {
                    lObj.State_Union_Territory_Province__c = state.Id;
                }
            }
            for (Country__c country : countryList) {
                if (country.Name == lObj.Country) {
                    lObj.Country__c = country.Id;
                }
            }
        }
        
        if (label.Round_Robin_Switch == 'true'){
            
            for (Lead lObj : Trigger.new) {
                
                if (lObj.Round_Robin_No__c ==null){ //Entry Condition for UPDATE operation
                    
                    if(String.IsNotBlank(lObj.School_State__c)){
                        stateId.add(lObj.School_State__c);
                    }else{
                        stateId.add(lObj.State_Union_Territory_Province__c);
                    }
                }
            }
            
            //Vijai Round Robin user Asignment 10-05-2023
            Map<Id, Decimal> nextSeqMap = new  Map<Id, Decimal>();
            for(State__c st : [SELECT Id, Name, Next_sequence_no__c FROM State__c WHERE Id IN :stateId]){
                nextSeqMap.put(st.Id, st.Next_sequence_no__c);
            }
            
            Map<Id, Id> userMap = new  Map<Id, Id>();
            Map<Id, Id> userIdMap = new  Map<Id, Id>();
            List<Round_Robin_User__c> rruserToUpdate = new List<Round_Robin_User__c>();
            for(Round_Robin_User__c rruser : [SELECT Id, Name, Active__c, Sequence_Number__c, Record_Last_Added__c, User__c, State__c 
                                              FROM Round_Robin_User__c WHERE Active__c = true AND State__c IN :stateId ]){
                                                  
                                                  system.debug('Matching sequence number  ***' +rruser.Sequence_Number__c);
                                                  system.debug('State Nextsequence number  ***' +nextSeqMap.get(rruser.State__c));     
                                                  
                                                  if(rruser.Sequence_Number__c == nextSeqMap.get(rruser.State__c)){
                                                      system.debug('Matching sequence number is identified ***' +rruser.Sequence_Number__c);
                                                      userMap.put(rruser.State__c, rruser.User__c);
                                                      userIdMap.put(rruser.State__c, rruser.Id);
                                                      rruser.Record_Last_Added__c = true; //Updating the Roundrobin user as true;
                                                      rruserToUpdate.add(rruser);
                                                  }
                                              }
            
            //If No State is provided then default user takes the OwnerShip
            List<user> defaultUser = [SELECT Id, Name FROM user WHERE Name = 'Swarnmani Singh'];
            
            for (Lead lObj : Trigger.new) {
                
                system.debug('inside final for');
                
                if (lObj.Round_Robin_No__c ==null){
                    
                    system.debug('inside if No Round Round User Found ');
                    
                    if(nextSeqMap.values().size()>0){
                        
                        if(userMap.values().size()>0){
                            
                            system.debug('userMap Size is >0');
                            
                            if(String.IsNotBlank(lObj.School_State__c)){
                                lObj.OwnerId = userMap.get(lObj.School_State__c);
                                lObj.Round_Robin_No__c = userIdMap.get(lObj.School_State__c);
                            }
                            else if(String.IsNotBlank(lObj.State_Union_Territory_Province__c)){
                                lObj.OwnerId = userMap.get(lObj.State_Union_Territory_Province__c);
                                lObj.Round_Robin_No__c = userIdMap.get(lObj.State_Union_Territory_Province__c);
                            }
                        }
                    }else{
                        if(defaultUser.size()>0){
                            system.debug('No State is Provided**');
                            lObj.OwnerId = defaultUser[0].Id;
                        }
                    }
                }
            }
            
            if(rruserToUpdate.size()>0){
                UPDATE rruserToUpdate;
            }
        }
        // }
    }
}