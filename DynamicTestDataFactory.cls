/*
 * This is structurally unstable exploratory code. It is not production-ready, does not follow best practices,
 * and is not suitable for orgs with complex or sensitive data models. It has been tested on orgs with up to
 * 1,000 SObjects, but there's no guarantee it will behave safely or correctly beyond that. It attempts to
 * populate an org with one of (almost) every createable object and resolve their required reference fields
 * recursively. 
 *
 * Expect unpredictable behavior, silent failures, undocumented platform quirks, and substantial mental overhead
 * if you try to follow the logic end-to-end. It does, however, mostly work. Viewer discretion advised.
 */

 public with sharing class DynamicTestDataFactory {

    public static final Set<String> SETUP_OBJECTS = new Set<String>{
        'authorizedemaildomain','businessprocess','caseteamrole','caseteamtemplate','cleandataservice',
        'cleanrule','compactlayout','compactlayoutinfo','compactlayoutiteminfo','customfield',
        'customfieldmember','customobject','customtab','dataassessmentconfigitem',
        'dataintegrationrecordpurchasepermission','duplicatejobdefinition','duplicatejobmatchingruledefinition',
        'document','emailtemplate','entitydefinition','entitylimit','fielddefinition','fieldmapping',
        'fieldmappingfield','fieldmappingrow','fieldset','flexipage','flow','flowdefinition','group',
        'historyretentionjob','keywordlist','layout','lookupfilter','matchingrule','menuitem','moderationrule',
        'profile','profilelayout','quickactiondefinition','quickactionlist','quickactionlistitem',
        'recentlyviewed','recordtype','searchlayout','scontrol','user','userrole','weblink',
        'validationrule','workflowalert','workflowfieldupdate','workflowoutboundmessage','workflowrule',
        'workflowtask'
    };

    private static Map<String,SObjectType> masterMap;
    private static List<SObject> insList;
    private static List<SObjectWrapper> unresolved;
    private static Map<SObjectType,Id> soMap; 

    /**
     * Attempts to create and optionally insert one instance of every insertable SObject in the org.
     * 
     * @param isInsert whether to insert the generated objects into the database
     * @param resolveDependencies whether to recursively resolve and populate reference fields
     * @return list of generated (and possibly inserted) SObjects
     */
    public static List<Object> makeOneOfEachInsertableSObject(Boolean isInsert, Boolean resolveDependencies) {
        masterMap = Schema.getGlobalDescribe();
        insList = new List<SObject>();
        unresolved = new List<SObjectWrapper>();
        
        for(String s : masterMap.keySet()) {
            populateFields(s);
        }

        if(isInsert) {
            insertionHelper();
            if(resolveDependencies) {
                return (List<Object>) resolveDependencies();
            }
        }
        return insList;
    }

    /**
     * Attempts to populate all required and creatable fields on a given SObject type.
     * Reference fields are flagged for later dependency resolution.
     * 
     * @param s the API name of the SObject type
     */
    private static void populateFields(String s) {
        DescribeSObjectResult dsor;
        try {
            dsor = masterMap.get(s).getDescribe();
        } catch (Exception e) {
            return;
        }

        if (!dsor.isQueryable() || !dsor.isCreateable() || SETUP_OBJECTS.contains(s.toLowerCase())) return;

        SObjectWrapper sow = new SObjectWrapper(dsor);

        if(dsor.isAccessible() && dsor.isCreateable()) {
            Map<String,SObjectField> sofMap = dsor.fields.getMap();
            for(String s2 : sofMap.keySet()) {
                DescribeFieldResult dfr = sofMap.get(s2).getDescribe();
                DisplayType dType = dfr.getType();
                SObjectField sof = sofMap.get(s2);

                if(!dfr.isNillable() && dfr.isCreateable() && !dfr.isDefaultedOnCreate()) {
                    switch on dType {
                        when REFERENCE {
                            sow.unresList.add(sof);
                            sow.hasUnresolved = true;
                        }
                        when PICKLIST {
                            List<PicklistEntry> p = dfr.getPicklistValues();
                            sow.record.put(sof, !p.isEmpty() ? p[0].value : 'placeholderPICKLISTVAL' + (Math.random() * 1000).intValue());
                        }
                        when DATE {
                            sow.record.put(sof, Date.today());
                        }
                        when BOOLEAN {
                            sow.record.put(sof,false);
                        }
                        when DOUBLE {
                            sow.record.put(sof,Math.random() * 1000);
                        }
                        when STRING {
                            sow.record.put(sof,'placeholderSTRING' + (Math.random() * 1000).intValue());
                        }
                        when BASE64 {
                            sow.record.put(sof,Blob.valueOf('placeholderBASE64' + (Math.random() * 1000).intValue()));
                        }
                        when DATETIME {
                            sow.record.put(sof,Datetime.now());
                        }
                        when TEXTAREA {
                            sow.record.put(sof,'placeholderTEXTAREA' + (Math.random() * 1000).intValue());
                        }
                        when CURRENCY {
                            sow.record.put(sof, (Math.random() * 1000));
                        }
                        when EMAIL {
                            sow.record.put(sof, 'aaaa@ffff.com');
                        }
                        when PHONE {
                            sow.record.put(sof,'1-222-333-4444');
                        }
                        when INTEGER {
                            sow.record.put(sof, (Math.random() * 1000).intValue());
                        }
                        when else {
                            // Skip unsupported types
                        }
                    }
                }
            }
            if(!sow.hasUnresolved) {
                insList.add(sow.record);
            } else {
                unresolved.add(sow);
            }
        }
    }

    /**
     * Seeds the dependency map and recursively resolves SObject reference fields.
     * 
     * @return list of inserted record Ids
     */
    private static List<Id> resolveDependencies() {
        if (soMap == null) soMap = new Map<SObjectType,Id>();
        for(Integer i = insList.size() - 1; i > -1; i--) {
            SObject so = insList[i];
            if(so.getSObjectType().getDescribe().fields.getMap().get('Id') != null) {
                soMap.put(so.getSObjectType(),so.Id);
            } else {
                insList.remove(i);
            }
        }
        return depRecurse();
    }

    /**
     * Recursive resolver that peels off resolvable SObjects layer by layer and inserts them.
     * 
     * @return list of resolved and inserted record Ids
     */
    private static List<Id> depRecurse() {
        if (unresolved.isEmpty()) return soMap.values();

        List<SObject> chunkList = new List<SObject>();
        List<SObjectWrapper> checkList = new List<SObjectWrapper>();

        for (SObjectWrapper sow : unresolved) {
            sow.hasUnresolved = false;
            for (SObjectField sof : sow.unresList) {
                Boolean found = false;
                try {
                    List<SObjectType> refTypes = sof.getDescribe().getReferenceTo();
                    if (refTypes.isEmpty()) {
                        sow.hasUnresolved = true;
                        continue;
                    }
                    for (SObjectType refType : refTypes) {
                        Id refId = soMap.get(refType);
                        if (refId != null) {
                            sow.record.put(sof, refId);
                            found = true;
                            break;
                        }
                    }
                } catch (Exception e) {
                    sow.hasUnresolved = true;
                    continue;
                }
                if (!found) sow.hasUnresolved = true;
            }
            if (!sow.hasUnresolved) {
                chunkList.add(sow.record);
            } else {
                checkList.add(sow);
            }
        }

        insList = chunkList;
        insertionHelper();

        for (SObject so : insList) {
            soMap.put(so.getSObjectType(), so.Id);
        }

        if (unresolved == checkList) return soMap.values();
        unresolved = checkList;
        return depRecurse();
    }

    /**
     * Inserts a list of SObjects in batches of 10, removing any failed insertions.
     */
    private static void insertionHelper() {
        Integer inserted = 0;
        Integer excepted = 0;
        Integer size = insList.size();
        List<Integer> removeIndices = new List<Integer>();

        for(Integer i = 0; i < size; i += 10) {
            List<SObject> localList = new List<SObject>();
            for(Integer i2 = i; i2 < Math.min(i + 10,size); i2++) {
                localList.add(insList[i2]);
            }
            List<Database.SaveResult> tempList = Database.insert(localList,false);
            for(Integer i2 = 0; i2 < tempList.size(); i2++) {
                Database.SaveResult sr = tempList[i2];
                if(sr.isSuccess()) {
                    inserted++;
                } else {
                    excepted++;
                    removeIndices.add(i + i2);
                }
            }
        }
        Integer offset = 0;
        for(Integer i : removeIndices){
            insList.remove(i - offset++);
        }
    }

    /**
     * Wrapper to preserve mutability and identity across reference resolution steps.
     */
    public class SObjectWrapper {
        SObject record;
        Boolean hasUnresolved;
        List<SObjectField> unresList;
        String sObjectName;

        public SObjectWrapper() {
            this.hasUnresolved = false;
            this.unresList = new List<SObjectField>();
        }

        public SObjectWrapper(DescribeSObjectResult dsor) {
            this.record = dsor.getSObjectType().newSObject();
            this.hasUnresolved = false;
            this.unresList = new List<SObjectField>();
            this.sObjectName = dsor.getName();
        }

        public SObjectWrapper(SObject so, Boolean b, List<SObjectField> l, String s) {
            this.record = so;
            this.hasUnresolved = b;
            this.unresList = l;
            this.sObjectName = s;
        }
    }
}
