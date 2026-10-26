/**
 * Webhook used by the ERP to send ONE pre-registered group for an existing Undergraduation lead.
 * POST /services/apexrest/UGPreRegistration
 * Body (single object or a list of objects):
 *   { "leadId": "00Q...", "grptag": "UG_Group2", "preRegister": true, "preRegistrationDate": "2026-05-01",
 *     "programmes": [ { "programInterestedIn": "...", "major": "..." } ]   // optional
 *   }
 * The group goes to the lead's next free slot (or updates the slot that already has this group).
 * No Opportunity is created. If the lead is already converted the Account is updated too.
 */
@RestResource(urlMapping='/UGPreRegistration')
global with sharing class UGPreRegistrationRest {

    @HttpPost
    global static String receive() {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        try {
            Object body = JSON.deserializeUntyped(RestContext.request.requestBody.toString());
            if (body instanceof List<Object>) {
                for (Object o : (List<Object>) body) out.add(handleOne((Map<String, Object>) o));
            } else if (body instanceof Map<String, Object>) {
                out.add(handleOne((Map<String, Object>) body));
            } else {
                out.add(new Map<String, Object>{ 'success' => false, 'message' => 'Error: Invalid payload format.' });
            }
        } catch (Exception e) {
            out.add(new Map<String, Object>{ 'success' => false, 'message' => 'Error: ' + e.getMessage() });
        }
        return JSON.serialize(out);
    }

    private static Map<String, Object> handleOne(Map<String, Object> p) {
        Savepoint sp = Database.setSavepoint();
        try {
            return LeadConversionService.savePreRegistrationGroup(p);
        } catch (Exception e) {
            Database.rollback(sp);
            return new Map<String, Object>{ 'success' => false, 'leadId' => p.get('leadId'), 'message' => 'Error: ' + e.getMessage() };
        }
    }
}