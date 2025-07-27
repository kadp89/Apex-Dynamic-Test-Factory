public with sharing class DynamicTestDataFactory {

    /*
     * Constructs one insertable record for every accessible and createable SObject type 
     * in the org. Fields are populated heuristically according to type; non-nullable 
     * references are deferred for dependency resolution.
     * 
     * If `isInsert` is true, records are inserted into the database. If 
     * `resolveDependencies` is also true, any unresolved foreign key relationships 
     * (REFERENCE fields) will be recursively resolved and inserted as well.
     * 
     * @param isInsert            Whether to perform a DML insert on constructed records.
     * @param resolveDependencies Whether to recursively resolve unresolved foreign key dependencies.
     */
    public static void makeOneOfEachInsertableSObject(Boolean isInsert, Boolean resolveDependencies) {
        
        final Map<String,SObjectType> masterMap = Schema.getGlobalDescribe();
        List<SObject> insList = new List<SObject>();
        List<SObjectWrapper> unresolved = new List<SObjectWrapper>();
        List<String> parentNames = new List<String>();

        for(String s : masterMap.keySet()) {

            DescribeSObjectResult dsor = masterMap.get(s).getDescribe();
            SObjectWrapper sow = new SObjectWrapper(dsor);

            if(dsor.isAccessible() && dsor.isCreateable()) {
                
                Map<String,SObjectField> sofMap = dsor.fields.getMap();

                for(String s2 : sofMap.keySet()) {

                    DescribeFieldResult dfr = sofMap.get(s2).getDescribe();
                    DisplayType dType = dfr.getType();
                    SObjectField sof = sofMap.get(s2);

                    if(!dfr.isNillable() && dfr.isCreateable() && !dfr.isDefaultedOnCreate()) {
                        // Hard-coded switch is ugly; this is the limit of SF's reflection
                        // Without the ability to dynamically instantiate primitives, this is what we've got
                        switch on dType {
                            when REFERENCE {
                                // Defer reference fields for post-insert resolution
                                sow.unresList.add(sof);
                                sow.hasUnresolved = true;
                            }
                            when PICKLIST {
                                List<PicklistEntry> p = dfr.getPicklistValues();
                                if(!p.isEmpty())
                                    sow.record.put(sof, p[0].value);
                                else 
                                    sow.record.put(sof, 'placeholderPICKLISTVAL');
                            }
                            when DATE {
                                sow.record.put(sof, Date.today());
                            }
                            when BOOLEAN {
                                sow.record.put(sof, false);
                            }
                            when DOUBLE {
                                sow.record.put(sof, Math.random());
                            }
                            when STRING {
                                sow.record.put(sof, 'placeholderSTRING');
                            }
                            when BASE64 {
                                sow.record.put(sof, Blob.valueOf('placeholderBASE64'));
                            }
                            when DATETIME {
                                sow.record.put(sof, Datetime.now());
                            }
                            when TEXTAREA {
                                sow.record.put(sof, 'placeholderTEXTAREA');
                            }
                            when CURRENCY {
                                sow.record.put(sof, Math.random());
                            }
                            when EMAIL {
                                sow.record.put(sof, 'aaaa@ffff.com');
                            }
                            when PHONE {
                                sow.record.put(sof, '1-222-333-4444');
                            }
                            when INTEGER {
                                sow.record.put(sof, (Math.random() * 1000).intValue());
                            }
                            when else {
                                // Intentionally ignored: unsupported or read-only types
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
        if(isInsert) {
            insert insList;
            if(resolveDependencies) {
                DynamicTestDataFactory.resolveDependencies(insList, unresolved);
            }
        } else {
            System.debug('We made the following: ');
            for(SObject s : insList)
                System.debug('\t' + s);
        }
    }

    /*
     * Initializes a Describe-result map for pre-inserted records and delegates 
     * to the recursive dependency resolver.
     *
     * @param parentList List of already-inserted records, used to resolve reference fields.
     * @param childList  List of wrappers containing unresolved reference fields.
     * @return All resolved and inserted SObjects, including those from recursion.
     */
    private static List<SObject> resolveDependencies(List<SObject> parentList, List<SObjectWrapper> childList) {
        
        Map<DescribeSObjectResult,SObject> soMap = new Map<DescribeSObjectResult,SObject>();
        
        for(SObject so : parentList) {
            DescribeSObjectResult s = so.getSObjectType().getDescribe();
            soMap.put(s, so);
        }
        
        return DynamicTestDataFactory.depRecurse(soMap, childList);
    }

    /* 
     * Recursively inserts SObjects whose reference fields depend on previously 
     * inserted records. Uses Describe information to match and resolve types 
     * dynamically at runtime.
     * 
     * Due to Salesforce's backend constraint on relationship depth (5 levels max), 
     * recursion is guaranteed to be stack-safe.
     * 
     * In each recursive pass:
     * - Reference fields are resolved using `soMap`
     * - Resolved records are inserted and added to the map
     * - Unresolved records are deferred to the next pass
     * 
     * Best-case: O(log n), where dependencies resolve in batch.
     * Worst-case: O(n!), if each record depends on the prior and only one can resolve per pass.
     * 
     * The worst case is only theoretical, as such dependency graphs cannot be 
     * constructed in real Salesforce schemas.
     *
     * @param soMap     Map of Describe results to resolved, inserted records.
     * @param childList List of unresolved wrappers to attempt resolution on.
     * @return All inserted SObjects after dependency resolution.
     */
    private static List<SObject> depRecurse(Map<DescribeSObjectResult,SObject> soMap, List<SObjectWrapper> childList) {
        if(childList.isEmpty()) {
            return soMap.values();
        } else {
            List<SObject> insList = new List<SObject>();
            List<SObjectWrapper> nextList = new List<SObjectWrapper>();
            for(SObjectWrapper sow : childList) {
                sow.hasUnresolved = false;
                DescribeSObjectResult dsor = sow.record.getSObjectType().getDescribe();
                for(SObjectField sof : sow.unresList) {
                    SObject temp = soMap.get(dsor);
                    if(temp != null) {
                        sow.record.put(sof, temp.Id);
                    } else {
                        sow.hasUnresolved = true;
                    }
                }
                if(!sow.hasUnresolved) { 
                    insList.add(sow.record);
                    soMap.put(dsor, sow.record);
                } else {
                    nextList.add(sow);
                }
            }
            insert insList;
            return DynamicTestDataFactory.depRecurse(soMap, nextList);
        }
    }

    /*
     * Lightweight wrapper for SObjects used to track unresolved reference fields 
     * across recursion. Apex does not guarantee reference stability for raw 
     * SObjects across iterations or mutation; wrapping the record provides a 
     * consistent reference surface and avoids implicit copy-on-write behavior.
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
