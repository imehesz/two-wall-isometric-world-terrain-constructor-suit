# Two Wall Isometric World Terrain Constructor Suit (TWIWCS)

## Overview
**Two Wall Isometric World Terrain Constructor Suit (TWIWCS)** is a lightweight, web-browser-based layout editor designed specifically for 2.5D isometric game development. 

As AI art generators make it easier to create stunning isometric assets (like buildings, furniture, and terrain), developers still face a massive bottleneck: manually slicing those images, calculating true 2:1 isometric projection math, and fixing complex Y-depth sorting issues in their game engines. 

**TWIWCS solves this problem.** It bridges the gap between raw sprite sheets and playable game levels.

## What It Does
TWIWCS provides a frictionless, drag-and-drop sandbox environment to test, assemble, and export isometric scenes. 

* **Seamless Asset Import:** Upload any pre-sliced sprite sheet alongside its metadata (TexturePacker JSON format) directly into your browser.
* **True Isometric Sandbox:** Paint and position your assets onto a mathematically perfect 2:1 isometric grid.
* **Precision Controls:** Fine-tune X/Y coordinates, scale, and flipping with micro-step modifier keys, while the editor automatically handles the headache of Y-depth sorting.
* **Engine-Ready Export:** Once your scene looks perfect, export the entire layout as a clean, structured JSON file that can be instantly parsed by engines like Unity, Godot, or Unreal.

## Technology
Built using **Godot 4** and deployed via **HTML5**, TWIWCS requires absolutely no installation or executable downloads. It runs entirely locally in your web browser.

## Use
LeshyLabs for slicing a sprite image (make sure to use JSON-TP_Array format): https://www.leshylabs.com/apps/sstool/
