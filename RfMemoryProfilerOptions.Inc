{	RfMemoryProfiler Options	}

{While INSTANCES_COUNTER on all the objects of the application will be counted.}
{$define INSTANCES_COUNTER}           

{While BUFFER_COUNTER on all the non-objects of the application will be counted and grouped by it's size.}
{$define BUFFER_COUNTER}               

{While INSTANCES_TRACKER the object allocator caller method will be identified and the object counter will be grouped by object type and caller method.
 To active this option you must active INSTANCES_COUNTER. Obs.: The TObject is not counted and tracket in this mode}
{$define INSTANCES_TRACKER}

{While INSTANCES_TRACKER the object allocator caller method will be identified and the object counter will be grouped by object type and caller method.
 To active this option you must active BUFFER_TRACKER}
{$define BUFFER_TRACKER}  