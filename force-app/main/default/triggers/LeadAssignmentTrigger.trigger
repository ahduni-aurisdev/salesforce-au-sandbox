/******************************************************************************************
* Created By       : Preksha Chauhan
* Company          : GetonCRM Solutions
* Trigger Name     : LeadAssignmentTrigger
* Created Date     : 08/20/2024
* Description      : Trigger for the Lead object to assign the lead owner based on preferred 
*                    programs and custom metadata configuration. 
*                    This trigger covers the following scenarios:
*                    - Before Insert: Invokes LeadAssignmentHelper to assign lead owners based 
*                      on the preferred program and record type configuration.
* Cover CodeCoverage: 100%
**********************************************************************************************/
//below is round robbin logic in sandbox org
/*trigger LeadAssignmentTrigger on Lead (before insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        // Filter leads to only those with the "Masters" record type
        List<Lead> mastersLeads = new List<Lead>();
        for (Lead lead : Trigger.new) {
            if (LeadAssignmentHelper.isMastersRecordType(lead.RecordTypeId)) {
                mastersLeads.add(lead);
            }
        }
        
        // Assign the filtered leads
        if (!mastersLeads.isEmpty()) {
            LeadAssignmentHelper.assignLeads(mastersLeads);
        }
    }
}*/

/*trigger LeadAssignmentTrigger on Lead (before insert) {
    LeadAssignmentHelper.handleBeforeInsert(Trigger.new);
}*/

trigger LeadAssignmentTrigger on Lead (before insert) {
    if (Trigger.isBefore && Trigger.isInsert) {
        // Filter leads for "Masters" and "PhD" record types
        List<Lead> mastersLeads = new List<Lead>();
        List<Lead> phdLeads = new List<Lead>();

        Map<String,String> recordTypeResponse = LeadAssignmentHelper.getRecordTypeWithName(); 
        
        for (Lead lead : Trigger.new) {
            if (recordTypeResponse.get(lead.RecordTypeId) == 'Masters') {
                mastersLeads.add(lead);
            } else if (recordTypeResponse.get(lead.RecordTypeId) == 'Phd') {
                phdLeads.add(lead);
            }
        }
        
        // Assign Masters leads
        if (!mastersLeads.isEmpty()) {
            LeadAssignmentHelper.assignLeads(mastersLeads);
        }
        
        // Assign PhD leads to Doctoral Admission User
        if (!phdLeads.isEmpty()) {
            LeadAssignmentHelper.assignPhdLeads(phdLeads);
        }
    }
}