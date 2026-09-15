<h1 align="center">Zing Zong</h1>

A Breakout game implementation in Zig with Raylib + ImGui

Tested with 
- Zig `0.16.0`
- ImGui `1.92.1-docking`
- Raylib `6.0.0`
- rlimgui `commit dc7f97679a024eee8f5f009e77cc311748200415`

[**▶️ Watch the DEMO**](https://youtu.be/z-iqwpSnDVA)

## How I got it to work...
At the time of writing this, zig is still on beta, so everything is subject to change, inspired in the work by schmee in [zig-raylib-imgui-template](https://github.com/schmee/zig-raylib-imgui-template) for zig 0.13, I did the same setup for zig 0.16.0. 

```
  Raylib ◄────── rlimgui  ◄────── ImGui
(dynamically                           
  linked)                              
     │                                 
     │                                 
     ▼                                 
 Executable                            
   (LLVM)                              
```

ImGui and Raylib are not meant to work together, so some _glue code_ is required by `rlimgui` to allow ImGui communicate with the backend provided by Raylib (GLFW). 

Also the Raylib library is actually *dinamically linked* and everything compiled with LLVM, due to some problems with my OS (Manjaro) at the time of building this project.

## How to run it 

``` bash
zig build         # Compile
zig build run     # Compile & run
zig build test    # Run tests
```

## Architecture

The architecture is heavely inspired in the drafts provided [by a post written by the creators of the match engine ](https://devlog.hexops.org/2022/lets-build-ecs-part-1/). The whole idea revolves around 2 main pillars: 

1. See the ECS as **Relational DB** with some sprinkles✨ on top.
2. The data should be as **thighly** pack as possible.

Those two directed the main design decisions and data structures, resulting :

- A **Game** is just a set of **Scenes**. 
- A **Scene** is composed of **Systems** and a **EntityDB**.
  - A **EntityDB** is a light Relational DB storing **Components** for each **Entity**.
  - A **System** is a set of callbacks that controls the behaviour of a set of entities.


A diagram might help :D! here are the Top-level structures:

![](./docs/architecture1.png)

If we go deep down in a **Scene** we will find an **EntityDB**, which works SUPER similar to a relational database, with the difference that **tables (Archetypes) are created on the fly**, and rows moved around them automatically.

**Why? you ask**

Its a memory optimization. The closer there are a set of items in memory, the less round trips the CPU requires to read them, and the less space they take. In our context, it means that **entities with the same combination of components should be stored together**, that is: *entities with the same schema should be stored on the same archetype. ('Archetype' and 'Table' are equivalent)*.

<p align="center">
<img src="./docs/architecture2.png" alt="Alt Text" width="50%" alignment="center">
</p>

Whenever you add/remove a component to and entity, you are changing its "archetype": If you add wings to a lizard 🦎 its no longer a lizard ITS A DRAGON 🐲! So to prevent mixing lizards with dragons, we create a new archetype in the DB automatically, like shown below.


![](./docs/architecture4.png)

**Then, Why the cryptic Archetype Names?**

Because they are hashes, **an Archetype name is the hash of its components names**. This design allows to query entities of any schema SUPER FAST: if you look for entities with only "scales", "reptiles" and "wings", you just have to compute its hash, and check if a table with the same name exists, if it does, you have guaranteed all its rows have those exact 3 components, basically O(1).

If your query for items not strictly (can have more items, than requested), you will have to ask each table if it has the components your are looking for, if they do, return all rows of that table, basically O(n).

### The Implementation
An Entity DB is composed of lots of arrays (to keep data as close as posible, remember?) Simply speaking:

1. A **Component Store** is an array of components of the same type.
2. An **Archetype Table** stores an array hashmap of **Component Stores** which act as columns.
3. BUT, since we don't know the columns types in advance, we need to make them generic through *IComponentStore* interface, so any table can have columns of any type.
4. The **Archetype Table** Stores the list of entities it owns on `Entities` array.
5. The **EntityDB** stores and array hasmap of **Archetype tables** where the key is each table hash.
6. The **EntityDB** stores and array hasmap of **Entities**, where the key is an entity ID, and the value is the index of the table and the row where it currently lives.

![](./docs/architecture3.png). 


## Debugging tools
The debugging tools were also a challenge. They provide a direct way to interact with all the previous structures mentioned before WHILE THE GAME IS RUNNING.

Imagining you have a `position` component:
```c
const position = struct {
  x : i32 = 0;
  y : i32 = 0;
  z : i32 = 0;
}
```
If you were to edit the values of this position, you will need to know its fields, sizes and offsets, but since the type is erased when storing them (as mentioned on `Implementation`), its no longer posible after compilation (the notion of `type` doesn't exist on runtime).

### The Solution
Store the necesary type info before the compilation ends on a struct `TypeDescriptor`. Whenever we need to edit a component in runtime, we just check this struct, which tells us, all what we need about that type. Check `./src/ecs/reflect.zig` for more info 