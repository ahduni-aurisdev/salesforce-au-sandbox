public class LeadAssignmentCtrl {
     @InvocableMethod(label='Assign Lead' description='Assign Lead Using Lead ')
    public static void runAssignmentRules(List<Id> leadId) {
 		Id CurrentLeadId = leadId[0];
        Database.DmlOptions dmlOptions = new Database.DmlOptions();
        dmlOptions.assignmentRuleHeader.UseDefaultRule = true;
        Lead record = [Select Id,Name From Lead WHERE Id = :CurrentLeadId ];
        record.setOptions(dmlOptions);
        update record;
    }
}