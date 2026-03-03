public class UserPermissionReport {
    public static void generateCSVReport() {
        String csv = 'UserId,UserName,ProfileName,PermissionSetName,ObjectType,PermissionsRead,PermissionsCreate,PermissionsDelete,PermissionsEdit,RecordTypeName\n';
        
        // Get Users with Profiles
        List<User> users = [SELECT Id, Name, ProfileId, Profile.Name FROM User];
        
        // Get User Permission Sets
        Map<Id, List<PermissionSetAssignment>> userPermissions = new Map<Id, List<PermissionSetAssignment>>();
        for (PermissionSetAssignment pset : [SELECT AssigneeId, PermissionSet.Name FROM PermissionSetAssignment]) {
            if (!userPermissions.containsKey(pset.AssigneeId)) {
                userPermissions.put(pset.AssigneeId, new List<PermissionSetAssignment>());
            }
            userPermissions.get(pset.AssigneeId).add(pset);
        }
        
        // Get Object Permissions by Profile
        Map<Id, List<ObjectPermissions>> profileObjectPermissions = new Map<Id, List<ObjectPermissions>>();
        for (ObjectPermissions op : [SELECT Parent.ProfileId, SObjectType, PermissionsRead, PermissionsCreate, PermissionsDelete, PermissionsEdit FROM ObjectPermissions WHERE Parent.ProfileId != null]) {
            if (!profileObjectPermissions.containsKey(op.Parent.ProfileId)) {
                profileObjectPermissions.put(op.Parent.ProfileId, new List<ObjectPermissions>());
            }
            profileObjectPermissions.get(op.Parent.ProfileId).add(op);
        }
        
        // Get Record Type Access by Profile
        Map<Id, List<String>> profileRecordTypeAccess = new Map<Id, List<String>>();
        List<RecordType> recordTypes = [SELECT Id, SObjectType, DeveloperName FROM RecordType WHERE SObjectType = 'YourObjectName'];
        for (RecordType rt : recordTypes) {
            List<Profile> profiles = new List<Profile>();
            for (ObjectPermissions op : [SELECT ParentId FROM ObjectPermissions WHERE SObjectType = :rt.SObjectType]) {
                profiles.add([SELECT Id FROM Profile WHERE Id = :op.ParentId]);
            }
            for (Profile profile : profiles) {
                if (!profileRecordTypeAccess.containsKey(profile.Id)) {
                    profileRecordTypeAccess.put(profile.Id, new List<String>());
                }
                profileRecordTypeAccess.get(profile.Id).add(rt.DeveloperName);
            }
        }
        
        // Combine results and build CSV content
        for (User u : users) {
            String userId = u.Id;
            String userName = u.Name;
            String profileName = u.Profile.Name;
            
            String permissionSetNames = '';
            if (userPermissions.containsKey(u.Id)) {
                for (PermissionSetAssignment pset : userPermissions.get(u.Id)) {
                    permissionSetNames += pset.PermissionSet.Name + ';';
                }
            }
            permissionSetNames = permissionSetNames.removeEnd(';');
            
            String objectPermissions = '';
            if (profileObjectPermissions.containsKey(u.ProfileId)) {
                for (ObjectPermissions op : profileObjectPermissions.get(u.ProfileId)) {
                    objectPermissions += op.SObjectType + ' [Read: ' + op.PermissionsRead + ', Create: ' + op.PermissionsCreate + ', Edit: ' + op.PermissionsEdit + ', Delete: ' + op.PermissionsDelete + '];';
                }
            }
            objectPermissions = objectPermissions.removeEnd(';');
            
            String recordTypeNames = '';
            if (profileRecordTypeAccess.containsKey(u.ProfileId)) {
                for (String rtName : profileRecordTypeAccess.get(u.ProfileId)) {
                    recordTypeNames += rtName + ';';
                }
            }
            recordTypeNames = recordTypeNames.removeEnd(';');
            
            csv += userId + ',' + userName + ',' + profileName + ',' + permissionSetNames + ',' + objectPermissions + ',' + recordTypeNames + '\n';
        }
        
        // Create a file and save it in the Files
        ContentVersion cv = new ContentVersion();
        cv.Title = 'UserPermissionReport.csv';
        cv.PathOnClient = 'UserPermissionReport.csv';
        cv.VersionData = Blob.valueOf(csv);
        insert cv;
        
        System.debug('CSV Report generated: ' + cv.Id);
    }
}