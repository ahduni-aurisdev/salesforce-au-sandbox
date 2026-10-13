({
    doInit : function(component, event, helper) {
        
        var action = component.get("c.clickToCall");
        action.setParams({ 'recordId' : component.get("v.recordId") }); 
        action.setCallback(this, function(response) {
            var state = response.getState();
            
            if (state === "SUCCESS") {
                {
  var toastEvent = $A.get("e.force:showToast");
    toastEvent.setParams({
        "title": "Success!",
        "message": "Call will connect shortly.",
        "type":"success"
    });
    toastEvent.fire();                    
                }
            }else if (state === "ERROR") {
                var errors = response.getError();
                var toastMessage=''
                if (errors) {
                    if (errors[0] && errors[0].message) {
                        console.log("Error message: " + errors[0].message);
                        toastMessage =  errors[0].message;
                    }
                } else {
                     toastMessage =  'Unknown error';
                    console.log("Unknown error");
                }
                  var toastEvent = $A.get("e.force:showToast");
    				toastEvent.setParams({
        				"title": "Error!",
        				"message": toastMessage,
                        "type":"error"
    					});
    					toastEvent.fire();
            } 
            
            $A.get("e.force:closeQuickAction").fire();

        });  
        $A.enqueueAction(action); 

    }
})