"""Prepara l'isola volante per RealityKit, senza aprire Blender.

Uso:
    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
        -P Tools/Blender/crea_asset_isola.py -- <FloatingIsland.usdc> <cartella di uscita>

Cosa fa (e perché):
- Il file originale punta a texture esterne (./textures/*_BaseColor.png) che non esistono: i colori veri
  sono nei colori per vertice (primvar `Col`), che RealityKit non disegna. Lo script li "cuoce" in una
  texture per mesh usando le UV già presenti e rifà il materiale PBR (base color + roughness).
- Origine spostata alla base del tronco, all'altezza del terreno: in RealityKit l'albero è l'ancora
  della scena e il drago gli gira attorno senza offset magici nel codice.
- Esporta un USDZ Y-up con le texture dentro (nessun file esterno da dimenticare) e senza colori per
  vertice (inutili dopo la cottura, solo peso).
"""
import math
import os
import sys

import bpy

argomenti = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argomenti) != 2:
    raise SystemExit("Usage: ... -- <FloatingIsland.usdc> <output folder>")
SORGENTE, USCITA = (os.path.abspath(a) for a in argomenti)
os.makedirs(USCITA, exist_ok=True)
CARTELLA_TEXTURE = os.path.join(USCITA, "textures_isola")
os.makedirs(CARTELLA_TEXTURE, exist_ok=True)

# Risoluzione della texture cotta per mesh: l'isola ha molti più colori distinti di rocce e albero.
RISOLUZIONE = {"Island": 2048, "Tree": 1024, "FloatingRocks": 512}

# Scena vuota, poi import (Blender converte in Z-up).
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.wm.usd_import(filepath=SORGENTE, import_materials=False, read_mesh_colors=True)

mesh = {o.name: o for o in bpy.context.scene.objects if o.type == "MESH"}
for nome in RISOLUZIONE:
    if nome not in mesh:
        raise SystemExit(f"Missing mesh '{nome}' in {SORGENTE}")

# --- Trasformazioni applicate: ogni mesh in coordinate del mondo, senza genitori -------------------
for oggetto in mesh.values():
    matrice = oggetto.matrix_world.copy()
    oggetto.parent = None
    oggetto.matrix_world = matrice
    bpy.context.view_layer.objects.active = oggetto
    for o in bpy.context.scene.objects:
        o.select_set(o == oggetto)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in list(bpy.context.scene.objects):
    if o.type != "MESH":
        bpy.data.objects.remove(o)

# --- Origine alla base del tronco, sul terreno ------------------------------------------------------
albero = [v.co.copy() for v in mesh["Tree"].data.vertices]
z_minimo = min(p.z for p in albero)
base = [p for p in albero if p.z < z_minimo + 0.04]
cx = sum(p.x for p in base) / len(base)
cy = sum(p.y for p in base) / len(base)
# Il tronco affonda nel terreno: l'origine va sulla superficie dell'isola vicino al tronco.
vicini = [v.co.z for v in mesh["Island"].data.vertices if math.hypot(v.co.x - cx, v.co.y - cy) < 0.2]
terreno = max(vicini) if vicini else z_minimo
for oggetto in mesh.values():
    for v in oggetto.data.vertices:
        v.co.x -= cx
        v.co.y -= cy
        v.co.z -= terreno
print(f"Origin moved to the tree trunk: ({cx:.3f}, {cy:.3f}, {terreno:.3f}) in the source file")

# --- Cottura dei colori per vertice ------------------------------------------------------------------
scena = bpy.context.scene
scena.render.engine = "CYCLES"
scena.cycles.device = "CPU"
scena.cycles.samples = 1
scena.render.bake.margin = 8

for nome, risoluzione in RISOLUZIONE.items():
    oggetto = mesh[nome]
    dati = oggetto.data
    colore = dati.color_attributes.get("Col") or (dati.color_attributes[0] if dati.color_attributes else None)
    if colore is None:
        raise SystemExit(f"Mesh '{nome}' has no vertex colors to bake")
    uv = dati.uv_layers.get("st") or dati.uv_layers.get("UVMap") or dati.uv_layers[0]
    uv.name = "st"
    dati.uv_layers.active = uv

    immagine = bpy.data.images.new(f"{nome}_BaseColor", risoluzione, risoluzione, alpha=False)
    immagine.colorspace_settings.name = "sRGB"

    # Materiale temporaneo: colore per vertice -> emissione, cotta nella texture attiva.
    materiale = bpy.data.materials.new(f"{nome}_Mat")
    materiale.use_nodes = True
    nodi = materiale.node_tree.nodes
    collegamenti = materiale.node_tree.links
    nodi.clear()
    uscita = nodi.new("ShaderNodeOutputMaterial")
    emissione = nodi.new("ShaderNodeEmission")
    attributo = nodi.new("ShaderNodeVertexColor")
    attributo.layer_name = colore.name
    collegamenti.new(attributo.outputs["Color"], emissione.inputs["Color"])
    collegamenti.new(emissione.outputs["Emission"], uscita.inputs["Surface"])
    texture = nodi.new("ShaderNodeTexImage")
    texture.image = immagine
    nodi.active = texture
    dati.materials.clear()
    dati.materials.append(materiale)

    for o in scena.objects:
        o.select_set(o == oggetto)
    bpy.context.view_layer.objects.active = oggetto
    bpy.ops.object.bake(type="EMIT", margin=8, use_clear=True)
    immagine.filepath_raw = os.path.join(CARTELLA_TEXTURE, f"{nome}_BaseColor.png")
    immagine.file_format = "PNG"
    immagine.save()

    # Materiale finale: PBR opaco (si integra con la luce reale in mixed reality).
    nodi.remove(emissione)
    nodi.remove(attributo)
    bsdf = nodi.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.9
    bsdf.inputs["Metallic"].default_value = 0.0
    collegamenti.new(texture.outputs["Color"], bsdf.inputs["Base Color"])
    collegamenti.new(bsdf.outputs["BSDF"], uscita.inputs["Surface"])

    # I colori per vertice non servono più: solo peso nel file.
    dati.color_attributes.remove(colore)
    print(f"Baked {nome}: {len(dati.polygons)} faces, {risoluzione}px texture")

# --- Export ----------------------------------------------------------------------------------------
for o in scena.objects:
    o.select_set(o.name in mesh)
destinazione = os.path.join(USCITA, "FloatingIsland.usdz")
bpy.ops.wm.usd_export(filepath=destinazione, selected_objects_only=True, export_animation=False,
                      export_materials=True, generate_preview_surface=True, export_mesh_colors=False,
                      export_textures_mode="NEW", overwrite_textures=True,
                      convert_orientation=True, export_global_forward_selection="NEGATIVE_Z",
                      export_global_up_selection="Y", root_prim_path="/FloatingIsland")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(USCITA, "isola.blend"))
print(f"Island asset written to {destinazione}")
