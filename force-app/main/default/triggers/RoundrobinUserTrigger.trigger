trigger RoundrobinUserTrigger on Round_Robin_User__c (before Insert, before Update) {

    if(trigger.IsBefore && trigger.IsInsert){
        Set<Id> UserId = new Set<Id>();
        Set<Id> StateId = new Set<Id>();
        Set<Decimal> SequenceNumber = new  Set<Decimal>();

        for(Round_Robin_User__c rr : trigger.new) {
            StateId.add(rr.State__c);
            UserId.add(rr.User__c);
            SequenceNumber.add(rr.Sequence_Number__c);
        }

        Map<Id,Id> userMap = new Map<Id,Id>();
        For(Round_Robin_User__c ruser : [SELECT Id, Name, User__c, State__c FROM Round_Robin_User__c WHERE State__c IN :StateId
                                        AND User__c IN :UserId]){
            userMap.put(ruser.State__c, ruser.User__c);
        }

        Map<Id,Decimal> SequenceMap = new Map<Id,Decimal>();
        For(Round_Robin_User__c ruser : [SELECT Id, Name, Sequence_Number__c, State__c FROM Round_Robin_User__c WHERE State__c IN :StateId
                                        AND Sequence_Number__c IN :SequenceNumber]){
            SequenceMap.put(ruser.State__c, ruser.Sequence_Number__c);
        }

        for(Round_Robin_User__c rr : trigger.new) {

            if(rr.User__c == userMap.get(rr.State__c)){
                rr.addError('The User is Already added');
            }

            if(rr.Sequence_Number__c == SequenceMap.get(rr.State__c)){
                rr.addError('The Sequence Number is Already present');
            }

            if(String.IsBlank(rr.User__c)){
                rr.addError('Kindly provide the User field');
            }
        }

    }

    if(trigger.IsBefore && trigger.IsUpdate){

        Set<Id> stateId = new Set<Id>();
        Set<Id> rruserId = new Set<Id>();
        List<Round_Robin_User__c> To_uncheckList = new List<Round_Robin_User__c>();
        List<Round_Robin_User__c> rruserListToUpdate = new List<Round_Robin_User__c>();

        for(Round_Robin_User__c rr : trigger.new) {
            stateId.add(rr.State__c);
            rruserId.add(rr.Id);
        }
        
        
        Map<Id, List<Round_Robin_User__c>> RoundrobinuserMap = new Map<Id, List<Round_Robin_User__c>>();
        
        for(Round_Robin_User__c rr :[SELECT Id, Name, State__c, Record_Last_Added__c FROM Round_Robin_User__c 
                                    WHERE State__c =:stateId AND Record_Last_Added__c = true AND Id NOT in :rruserId]){

             if(RoundrobinuserMap.containsKey(rr.State__c)) {
                RoundrobinuserMap.get(rr.State__c).add(rr);
            }
            else
            RoundrobinuserMap.put(rr.State__c, new list<Round_Robin_User__c>{rr});
        }

        for(Round_Robin_User__c rru : trigger.new){

            if(rru.Sequence_Number__c == rru.State_Sequence_No_Maximum__c && rru.Record_Last_Added__c == true) {
                system.debug('****Making Final Maximumuser as False****');
                rru.Record_Last_Added__c = false; //Making Final Maximumuser as False
                if(RoundrobinuserMap.containsKey(rru.State__c)){
                    To_uncheckList = RoundrobinuserMap.get(rru.State__c);
                }        
            }
        }

        system.debug('**To_uncheckList size **'+To_uncheckList.size());

        if(To_uncheckList.size()>0){
            
            for(Round_Robin_User__c ruser: To_uncheckList){ //Making the list of RR Users as False
                ruser.Record_Last_Added__c = false;
                system.debug('**** ruser.Record_Last_Added__c ****'+ ruser.Record_Last_Added__c);
                rruserListToUpdate.add(ruser);
           }
    
           if(rruserListToUpdate.size()>0)
              UPDATE rruserListToUpdate;
        }
        
    }
}