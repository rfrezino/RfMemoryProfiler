RfMemoryProfiler
================
- Functionality: The feature developed in this unit to watch how the memory are being allocated by your system. The main
    focus of it is help to find memory leak in the most non intrusive way on a real time mode.

- How to Install: Put this unit as the first unit of yout project. If use use a third memory manager put this unit just after the
    unit of your memory manager.

- How to get it's report: It's not the final version of this unit, so the viewer was not developed. By the moment you can call
  the method SaveMemoryProfileToFile. It'll create a text file called RfMemoryReport in the executable path.

 ***** WARNING: If you use the space of the VMT destinated to vmtAutoTable, you should not use the directive TRACEINSTANCES *****

How it works:
The feature work in two different approaches:
1) Map the memory usage by objects
2) Map the memory usage by buffers (Records, strings and so on)
3) Map the memory usage by objects / Identify the method that called the object creation
4) Map the memory usage by buffers (Records, strings and so on) / Identify the method that called the buffer allocation

How are Objects tracked ?
  The TObject.NewInstance was replaced by a new method (TObjectHack.NNewInstanceTrace).
  So when the creation of an object is called it's redirect to the new method. In this new method is increased the counter of the relative class and change the method in the VMT that is responsible to free the object to a new destructor method (vmtFreeInstance). This new destructor call the decrease of the counter and the old destructor.
  This way I can know how much of objects of each class are alive in the system.

  (More details about how it deep work can be found in the comments on the code)

How are Memory Buffer tracked ?
  The GetMem, FreeMem, ReallocMem, AllocMem were replaced by new method that have an special behavior to help track the buffers.

   As the memory allocation use the same method to every kind of memory request, I'm not able to create a single counter to each count of buffer. So, I calculate them base on it size. First I create a array of integer that start on 0 and goes to 65365.
  When the system ask me to give it a buffer of 65 bytes, I increase the position 65 of the array and the buffer is deallocated I call the decrease of the position of the array corresponding to buffer size. If the size requested to the buffer is bigger or equal to 65365, I'll use the position 65365 of the array.

  (More details about how it deep work can be found in the comments on the code)

Develop by  Rodrigo Farias Rezino
    E-mail: rodrigofrezino@gmail.com
    Stackoverflow: http://stackoverflow.com/users/225010/saci
     Please, any bug let me know

