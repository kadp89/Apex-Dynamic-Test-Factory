public with sharing class DynamicTestDataFactory {

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
                       switch on dType {
                            when REFERENCE {
                                sow.unresList.add(sof);
                                sow.hasUnresolved = true;
                            }
                            when PICKLIST {
                                List<PicklistEntry> p = dfr.getPicklistValues();
                                if(!p.isEmpty())
                                    sow.record.put(sof, p[0].value);
                                else sow.record.put(sof, 'placeholderPICKLISTVAL');
                            }
                            when DATE {
                                sow.record.put(sof, Date.today());
                            }
                            when BOOLEAN {
                                sow.record.put(sof,false);
                            }
                            when DOUBLE {
                                sow.record.put(sof,Math.random());
                            }
                            when STRING {
                                sow.record.put(sof,'placeholderSTRING');
                            }
                            when BASE64 {
                                sow.record.put(sof,Blob.valueOf('placeholderBASE64'));
                            }
                            when DATETIME {
                                sow.record.put(sof,Datetime.now());
                            }
                            when TEXTAREA {
                                sow.record.put(sof,'placeholderTEXTAREA');
                            }
                            when CURRENCY {
                                sow.record.put(sof, (Math.random()));
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
                                //throw new Exception('something unhandled got through');
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
                system.debug('\t' + s);
        }
    }

    /*
     * pre-pass for recursion; prep the map and call recursive dependency resolver.
     * hard to estimate time complexity; nested function calls could be expensive behind
     * the scenes but are ultimately unavoidable
     */
    private static List<SObject> resolveDependencies(List<SObject> parentList, List<SObjectWrapper> childList) {
        
        Map<DescribeSObjectResult,SObject> soMap = new Map<DescribeSObjectResult,SObject>();
        
        for(SObject so : parentList) {
            DescribeSObjectResult s = so.getSObjectType().getDescribe();
            soMap.put(s,so);
        }
        
        return DynamicTestDataFactory.depRecurse(soMap, childList);
    }

    /* 
     * recursion is safe and elegant here; due to SF backend limitations on child 
     * relationship depth, it is impossible to hit apex stack depth limits.
     * size of childList decreases at a dynamic rate, peeling off one layer of children
     * at a time and passing the remainder to a recursive call 
     * at absolute best case, it's O(log n). at worst, it's... well, very expensive
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
                if(sow.hasUnresolved == false) { 
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
     * this wrapper is required because Apex is very finicky about preserving references.
     * if we don't wrap the generic SObject in a generic class, reference preservation is not
     * guaranteed across iterations and mutation. with a pointer to a naked SObject, mutating that
     * record results as often as not in undefined behavior. i suspect there may be hidden
     * and implicit whole-object creation going on behind the scenes; for whatever reason,
     * an indirection layer via wrapping sufficiently preserves a logical oasis for reference
     * stability.
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
