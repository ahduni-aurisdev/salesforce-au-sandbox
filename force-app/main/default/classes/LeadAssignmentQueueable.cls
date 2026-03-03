/******************************************************************************************
* Created By       : Preksha Chauhan
* Company          : GetonCRM Solutions
* Developer Name   : Preksha Chauhan
* Created Date     : 10/10/2024
* Class Name       : LeadAssignmentQueueable
* Description      : This class implements the Queueable interface to process Lead 
*                    assignments asynchronously. It takes a list of leads and a lead 
*                    type (Masters or PhD) as input parameters. Depending on the lead 
*                    type, it invokes the corresponding assignment methods from the 
*                    LeadHelper class to manage lead distribution. The class also 
*                    handles potential DML exceptions during the assignment process, 
*                    logging any errors encountered. This structure allows for efficient 
*                    handling of large volumes of lead assignments without hitting 
*                    governor limits.
**********************************************************************************************/
public class LeadAssignmentQueueable implements Queueable, Database.AllowsCallouts {
    private List<Lead> leadsToProcess;
    private String leadType;

    public LeadAssignmentQueueable(List<Lead> leads, String leadType) {
        this.leadsToProcess = leads;
        this.leadType = leadType;
    }

    public void execute(QueueableContext context) {
        try {
            if (leadType == 'Masters') {
                LeadHelper.assignLeads(leadsToProcess);
            } else if (leadType == 'Phd') {
                LeadHelper.assignLeadsByDepartment(leadsToProcess);
            }else if (leadType == 'Executive Education') {
                LeadHelper.assignLeadsByDepartment(leadsToProcess);
            }
            // else if (leadType == 'Undergraduation') {
            //     LeadHelper.assignUndergraduationLeads(leadsToProcess);
            // }
        } catch (DmlException e) {
            System.debug('Failed to assign leads due to: ' + e.getMessage());
        }
    }
}