This is kind of a frankenstein project where I wanted to try (and learn) some of the different nim libraries I might want to use.
- [Cat 400](https://github.com/c0ntribut0r/cat-400)
- [Synthesis](https://github.com/mratsim/Synthesis)
- [aglet](https://github.com/liquidev/aglet)


It works by having two main threads, one used for drawing and one for the actual gameplay logic. The drawing thread only draws something when the gameplay tells it to draw something new, which works fine for something with as infrequent updates as this program. There are however a few caviats with this:
- If the gameplay thread sends multiple messages in a row then the drawing thread might try to render some parts before everything is finished (tearing)
  - This can easily be fixed by having a "render" message telling the draw thread to render
- If the gameplay thread sends messages faster than the drawing thread can render everything the game will be stuck rendering forever
  - This can also be fixed by a render message, though then the render thread would end up really far behind the game.
  - Another alternative is to force it to finish rendering its current frame, then just skip messages to the latest of each kind.
  - A fun side-effect of having input events have priority is that even if this happens, you can still technically "play" the game without being able to see it
  - Due to the simplicity of this game, this is unlikely to happen, unless the user somehow mashes directional keys at an inhuman speed
- Fps counters will mark the game as having really low fps


In drawAutomaton I named some variables in reverse, IE. instead of \[name]'s \[variable type] (headPosition) I named it as \[variable type] of \[name] (positionHead).
I did this purely because I wanted to see what it would be like, though I was too lazy to change that many variables to this style. It is a bit confusing when naming stuff, but that might just be because I'm not used to it. Not sure if there's any advantage to this, might look better when stuff is grouped by type rather than by object?


Synthesis (and possibly also c4's spawn?) completely broke IntelliSense in Visual Studio code. I didn't bother asking if there's any way to fix this, and searching the web didn't give me any answers. It also messed a bit with how I set up my code, I ended up with one big file for each automaton, since I wasn't sure how to split up the state machine logic in a meaningful way. I also thought it broke the debugger, but turns out I just forgot to add the compile flags to the task.json when I stopped compiling the source code manually.


Using a state machine was obviously a bit much for such a small game project, but could definitely be useful in a bigger game. Due to missing a clean way to have multiple state machines that can be swapped between at any point of time, and no way to actually save/load the state of a machine at the fly, it's probably better suited for specialized tasks and menuing than actual game logic. Something more useful for games might be having the state machine as an object, then being able to call a function to make it progress. This could be simulated with having tons of threads (or async dispatches) with their own state-machine, then just have them wait for a message, but that probably would cause tons of needless delays.


Ultimately all the libraries did exactly what I wanted them to, Aglet was really good for removing all the useless boiler-plate code I normally need for windows and stuff, and worked really well with Synthesise. Synthesise allowed me to not have one giant loop (though obviously that would have been fine for this game), and for more complex state-handling it probably would help understand what logic happens when, especially with its graph generation tools. Cat 400 I only used the threads and messages of, but they worked. That said, for c4 I probably would prefer not having to use strings to declare the reciever of a message, and being able to use a case statement for the message-types automatically.