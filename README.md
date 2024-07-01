# A Defold library for generate .convexshape file from .glb file

---
##  How to use it
1. Add release `.zip` file in your project file `game.project -> Main -> Project -> Dependencies` and reopen your project;
2. Right click `.glb` file in your project and select `Generate convexshape file`, it will create a `*-convexshapes` folder and a `*collision game object` contains `.convexshape` in the folder before;
3. You can use this `.go` file as a collision shape, you can add model in this `.go` file, but you'd better **not** do that, because when you run this script to regenerate convexshape this `.go` file will be covered. You can put both `*collision.go` and a model in a `.go` file when this go file in a `collection` file.

## Current problems
1. Not support `Sparse Accessors` in glb files.
2. There still have 0.04 distance between two collision shapes, you can read this artical for detail <https://forum.defold.com/t/using-a-dae-mesh-for-collision/69434/3>.
3. Only test in simple models, so i dont know if it works in more complex models.