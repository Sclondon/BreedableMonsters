# Breedable Monsters

Breed polymons in a lab tank and sell them to keep the lab funded: reach 2500 credits within 20 days.
Every trait, body shape included, is genetic, so pairs breed children that blend and mutate their parents.

Godot **4.7**, Compatibility renderer, Jolt physics. Open `project.godot` and press F5.

## Controls

| | |
|---|---|
| Drop food | click the water |
| Select and follow a polymon | click it |
| Move one (between tanks, or a body into the disposal vat) | drag it |
| Orbit / zoom | right-drag / wheel |
| Start over | R |

## Web build

Published with GitHub Pages at <https://sclondon.github.io/BreedableMonsters/build/>.
To update it, export the **Web** preset
(`godot --headless --path . --export-release "Web" build/index.html`), commit `build/`, and push.
