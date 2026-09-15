# Element Templates

Copy-paste JSON templates for each Excalidraw element type. The `strokeColor` and `backgroundColor` values are placeholders — always pull actual colors from `color-palette.md` based on the element's semantic purpose.

## Free-Floating Text (no container)
```json
{
  "type": "text",
  "id": "label1",
  "x": 100, "y": 100,
  "width": 200, "height": 25,
  "text": "Section Title",
  "originalText": "Section Title",
  "fontSize": 20,
  "fontFamily": 3,
  "textAlign": "left",
  "verticalAlign": "top",
  "strokeColor": "<title color from palette>",
  "backgroundColor": "transparent",
  "fillStyle": "solid",
  "strokeWidth": 1,
  "strokeStyle": "solid",
  "roughness": 0,
  "opacity": 100,
  "angle": 0,
  "seed": 11111,
  "version": 1,
  "versionNonce": 22222,
  "isDeleted": false,
  "groupIds": [],
  "boundElements": null,
  "link": null,
  "locked": false,
  "containerId": null,
  "lineHeight": 1.25
}
```

## Line (structural, not arrow)
```json
{
  "type": "line",
  "id": "line1",
  "x": 100, "y": 100,
  "width": 0, "height": 200,
  "strokeColor": "<structural line color from palette>",
  "backgroundColor": "transparent",
  "fillStyle": "solid",
  "strokeWidth": 2,
  "strokeStyle": "solid",
  "roughness": 0,
  "opacity": 100,
  "angle": 0,
  "seed": 44444,
  "version": 1,
  "versionNonce": 55555,
  "isDeleted": false,
  "groupIds": [],
  "boundElements": null,
  "link": null,
  "locked": false,
  "points": [[0, 0], [0, 200]]
}
```

## Small Marker Dot
```json
{
  "type": "ellipse",
  "id": "dot1",
  "x": 94, "y": 94,
  "width": 12, "height": 12,
  "strokeColor": "<marker dot color from palette>",
  "backgroundColor": "<marker dot color from palette>",
  "fillStyle": "solid",
  "strokeWidth": 1,
  "strokeStyle": "solid",
  "roughness": 0,
  "opacity": 100,
  "angle": 0,
  "seed": 66666,
  "version": 1,
  "versionNonce": 77777,
  "isDeleted": false,
  "groupIds": [],
  "boundElements": null,
  "link": null,
  "locked": false
}
```

## Rectangle
```json
{
  "type": "rectangle",
  "id": "elem1",
  "x": 100, "y": 100, "width": 180, "height": 90,
  "strokeColor": "<stroke from palette based on semantic purpose>",
  "backgroundColor": "<fill from palette based on semantic purpose>",
  "fillStyle": "solid",
  "strokeWidth": 2,
  "strokeStyle": "solid",
  "roughness": 0,
  "opacity": 100,
  "angle": 0,
  "seed": 12345,
  "version": 1,
  "versionNonce": 67890,
  "isDeleted": false,
  "groupIds": [],
  "boundElements": [{"id": "text1", "type": "text"}],
  "link": null,
  "locked": false,
  "roundness": {"type": 3}
}
```

## Text (centered in shape)
```json
{
  "type": "text",
  "id": "text1",
  "x": 130, "y": 132,
  "width": 120, "height": 25,
  "text": "Process",
  "originalText": "Process",
  "fontSize": 16,
  "fontFamily": 3,
  "textAlign": "center",
  "verticalAlign": "middle",
  "strokeColor": "<text color — match parent shape's stroke or use 'on light/dark fills' from palette>",
  "backgroundColor": "transparent",
  "fillStyle": "solid",
  "strokeWidth": 1,
  "strokeStyle": "solid",
  "roughness": 0,
  "opacity": 100,
  "angle": 0,
  "seed": 11111,
  "version": 1,
  "versionNonce": 22222,
  "isDeleted": false,
  "groupIds": [],
  "boundElements": null,
  "link": null,
  "locked": false,
  "containerId": "elem1",
  "lineHeight": 1.25
}
```

## Arrow
```json
{
  "type": "arrow",
  "id": "arrow1",
  "x": 282, "y": 145, "width": 118, "height": 0,
  "strokeColor": "<arrow color — typically matches source element's stroke from palette>",
  "backgroundColor": "transparent",
  "fillStyle": "solid",
  "strokeWidth": 2,
  "strokeStyle": "solid",
  "roughness": 0,
  "opacity": 100,
  "angle": 0,
  "seed": 33333,
  "version": 1,
  "versionNonce": 44444,
  "isDeleted": false,
  "groupIds": [],
  "boundElements": null,
  "link": null,
  "locked": false,
  "points": [[0, 0], [118, 0]],
  "startBinding": {"elementId": "elem1", "focus": 0, "gap": 2},
  "endBinding": {"elementId": "elem2", "focus": 0, "gap": 2},
  "startArrowhead": null,
  "endArrowhead": "arrow"
}
```

## Fully-Bound Example (Movement-Safe Node + Connector)
```json
[
  {
    "type": "rectangle",
    "id": "nodeA",
    "x": 100,
    "y": 100,
    "width": 180,
    "height": 90,
    "strokeColor": "<stroke from palette>",
    "backgroundColor": "<fill from palette>",
    "fillStyle": "solid",
    "strokeWidth": 2,
    "strokeStyle": "solid",
    "roughness": 0,
    "opacity": 100,
    "angle": 0,
    "seed": 90101,
    "version": 1,
    "versionNonce": 90102,
    "isDeleted": false,
    "groupIds": [],
    "boundElements": [
      { "id": "labelA", "type": "text" },
      { "id": "arrowAB", "type": "arrow" }
    ],
    "link": null,
    "locked": false,
    "roundness": { "type": 3 }
  },
  {
    "type": "text",
    "id": "labelA",
    "x": 130,
    "y": 132,
    "width": 120,
    "height": 25,
    "text": "Source",
    "originalText": "Source",
    "fontSize": 16,
    "fontFamily": 3,
    "textAlign": "center",
    "verticalAlign": "middle",
    "strokeColor": "<text color>",
    "backgroundColor": "transparent",
    "fillStyle": "solid",
    "strokeWidth": 1,
    "strokeStyle": "solid",
    "roughness": 0,
    "opacity": 100,
    "angle": 0,
    "seed": 90103,
    "version": 1,
    "versionNonce": 90104,
    "isDeleted": false,
    "groupIds": [],
    "boundElements": null,
    "link": null,
    "locked": false,
    "containerId": "nodeA",
    "lineHeight": 1.25
  },
  {
    "type": "rectangle",
    "id": "nodeB",
    "x": 360,
    "y": 100,
    "width": 180,
    "height": 90,
    "strokeColor": "<stroke from palette>",
    "backgroundColor": "<fill from palette>",
    "fillStyle": "solid",
    "strokeWidth": 2,
    "strokeStyle": "solid",
    "roughness": 0,
    "opacity": 100,
    "angle": 0,
    "seed": 90105,
    "version": 1,
    "versionNonce": 90106,
    "isDeleted": false,
    "groupIds": [],
    "boundElements": [
      { "id": "labelB", "type": "text" },
      { "id": "arrowAB", "type": "arrow" }
    ],
    "link": null,
    "locked": false,
    "roundness": { "type": 3 }
  },
  {
    "type": "text",
    "id": "labelB",
    "x": 390,
    "y": 132,
    "width": 120,
    "height": 25,
    "text": "Target",
    "originalText": "Target",
    "fontSize": 16,
    "fontFamily": 3,
    "textAlign": "center",
    "verticalAlign": "middle",
    "strokeColor": "<text color>",
    "backgroundColor": "transparent",
    "fillStyle": "solid",
    "strokeWidth": 1,
    "strokeStyle": "solid",
    "roughness": 0,
    "opacity": 100,
    "angle": 0,
    "seed": 90107,
    "version": 1,
    "versionNonce": 90108,
    "isDeleted": false,
    "groupIds": [],
    "boundElements": null,
    "link": null,
    "locked": false,
    "containerId": "nodeB",
    "lineHeight": 1.25
  },
  {
    "type": "arrow",
    "id": "arrowAB",
    "x": 282,
    "y": 145,
    "width": 76,
    "height": 0,
    "strokeColor": "<arrow color>",
    "backgroundColor": "transparent",
    "fillStyle": "solid",
    "strokeWidth": 2,
    "strokeStyle": "solid",
    "roughness": 0,
    "opacity": 100,
    "angle": 0,
    "seed": 90109,
    "version": 1,
    "versionNonce": 90110,
    "isDeleted": false,
    "groupIds": [],
    "boundElements": null,
    "link": null,
    "locked": false,
    "points": [[0, 0], [76, 0]],
    "startBinding": { "elementId": "nodeA", "focus": 0, "gap": 2 },
    "endBinding": { "elementId": "nodeB", "focus": 0, "gap": 2 },
    "startArrowhead": null,
    "endArrowhead": "arrow"
  }
]
```

Use this when you need drag-safe behavior:
- Dragging `nodeA` or `nodeB` keeps its label attached (`containerId`).
- Connector `arrowAB` remains attached to both nodes (`startBinding`/`endBinding`).
- Reciprocal `boundElements` on shapes preserves relationship integrity in saved JSON.

For curves: use 3+ points in `points` array.
