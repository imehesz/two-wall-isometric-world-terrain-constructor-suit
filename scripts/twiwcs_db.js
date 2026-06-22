// twiwcs_db.js — IndexedDB persistence + .twiwcs archive for TWIWCS
// Loaded at runtime via:  JavaScriptBridge.eval(js_code)
// All functions accept a Godot callback (from JavaScriptBridge.create_callback).

var TWIWCS_DB = (function () {
    "use strict";

    const DB_NAME = "twiwcs_projects";
    const DB_VERSION = 1;
    let _db = null;

    // ── helpers ──────────────────────────────────────────────

    function _ok(cb, data) {
        if (cb) cb(JSON.stringify(data));
    }

    function _err(cb, msg) {
        if (cb) cb(JSON.stringify({ success: false, error: String(msg) }));
    }

    // ── init ─────────────────────────────────────────────────

    function init(callback) {
        if (_db) { _ok(callback, { success: true }); return; }

        var req = indexedDB.open(DB_NAME, DB_VERSION);

        req.onupgradeneeded = function (e) {
            var db = e.target.result;
            if (!db.objectStoreNames.contains("projects")) {
                db.createObjectStore("projects", { keyPath: "name" });
            }
            if (!db.objectStoreNames.contains("assets")) {
                var store = db.createObjectStore("assets", { keyPath: "key" });
                store.createIndex("project_name", "project_name", { unique: false });
            }
        };

        req.onsuccess = function (e) {
            _db = e.target.result;
            _ok(callback, { success: true });
        };

        req.onerror = function (e) {
            _err(callback, e.target.error ? e.target.error.message : "open failed");
        };
    }

    // ── save project ─────────────────────────────────────────
    // layoutJson  : string (Phase-B layout JSON)
    // assetsJson  : string — JSON array of {filename, png_base64, json_metadata}

    function saveProject(name, layoutJson, assetsJson, callback) {
        if (!_db) { _err(callback, "DB not initialized — call init() first"); return; }

        var tx = _db.transaction(["projects", "assets"], "readwrite");
        var projStore = tx.objectStore("projects");
        var assetStore = tx.objectStore("assets");

        // 1. Store layout
        projStore.put({ name: name, layout_json: layoutJson });

        // 2. Delete old assets for this project, then insert new ones
        var idx = assetStore.index("project_name");
        var range = IDBKeyRange.only(name);
        var oldKeys = [];
        var cursorReq = idx.openCursor(range);

        cursorReq.onsuccess = function (e) {
            var cursor = e.target.result;
            if (cursor) {
                oldKeys.push(cursor.primaryKey);
                cursor["continue"]();
            } else {
                // All old keys collected — delete them then insert new
                for (var i = 0; i < oldKeys.length; i++) {
                    assetStore["delete"](oldKeys[i]);
                }
                var assets = JSON.parse(assetsJson);
                for (var j = 0; j < assets.length; j++) {
                    assetStore.put({
                        key: name + "::" + assets[j].filename,
                        project_name: name,
                        filename: assets[j].filename,
                        png_base64: assets[j].png_base64,
                        json_metadata: assets[j].json_metadata,
                        json_path: assets[j].json_path || "",
                        set_id: assets[j].set_id
                    });
                }
            }
        };

        tx.oncomplete = function () {
            _ok(callback, { success: true });
        };
        tx.onerror = function (e) {
            _err(callback, e.target.error ? e.target.error.message : "save failed");
        };
    }

    // ── load project list ────────────────────────────────────

    function loadProjectList(callback) {
        if (!_db) { _err(callback, "DB not initialized"); return; }

        var tx = _db.transaction("projects", "readonly");
        var req = tx.objectStore("projects").getAllKeys();

        req.onsuccess = function (e) {
            _ok(callback, { success: true, names: e.target.result });
        };
        req.onerror = function (e) {
            _err(callback, e.target.error ? e.target.error.message : "list failed");
        };
    }

    // ── load project ─────────────────────────────────────────

    function loadProject(name, callback) {
        if (!_db) { _err(callback, "DB not initialized"); return; }

        var tx = _db.transaction(["projects", "assets"], "readonly");
        var projReq = tx.objectStore("projects").get(name);

        projReq.onsuccess = function (e) {
            var project = e.target.result;
            if (!project) {
                _err(callback, "Project not found: " + name);
                return;
            }

            // Fetch all assets via index
            var assetStore = tx.objectStore("assets");
            var idx = assetStore.index("project_name");
            var allReq = idx.getAll(IDBKeyRange.only(name));

            allReq.onsuccess = function (e2) {
                var rawAssets = e2.target.result || [];
                // Flatten to array of {filename, png_base64, json_metadata}
                var assets = [];
                for (var i = 0; i < rawAssets.length; i++) {
                    assets.push({
                        filename: rawAssets[i].filename,
                        png_base64: rawAssets[i].png_base64,
                        json_metadata: rawAssets[i].json_metadata,
                        json_path: rawAssets[i].json_path || "",
                        set_id: rawAssets[i].set_id
                    });
                }
                _ok(callback, {
                    success: true,
                    layout_json: project.layout_json,
                    assets_json: JSON.stringify(assets)
                });
            };

            allReq.onerror = function (e2) {
                _err(callback, e2.target.error ? e2.target.error.message : "assets fetch failed");
            };
        };

        projReq.onerror = function (e) {
            _err(callback, e.target.error ? e.target.error.message : "project fetch failed");
        };
    }

    // ── export .twiwcs (file download) ───────────────────────

    function exportTwiwcs(projectName, dataJson) {
        var blob = new Blob([dataJson], { type: "application/json" });
        var url = URL.createObjectURL(blob);
        var a = document.createElement("a");
        a.href = url;
        a.download = (projectName || "project") + ".twiwcs";
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }

    // ── import .twiwcs (file upload → callback) ──────────────

    function importTwiwcs(callback) {
        var input = document.createElement("input");
        input.type = "file";
        input.accept = ".twiwcs";
        input.style.display = "none";
        document.body.appendChild(input);

        input.onchange = function (e) {
            var file = e.target.files[0];
            if (!file) { document.body.removeChild(input); _err(callback, "No file selected"); return; }

            var reader = new FileReader();
            reader.onload = function (ev) {
                document.body.removeChild(input);
                // Pass the raw text back to Godot
                if (callback) callback(ev.target.result);
            };
            reader.onerror = function () {
                document.body.removeChild(input);
                _err(callback, "Read failed");
            };
            reader.readAsText(file);
        };

        input.click();
    }

    // ── public API ───────────────────────────────────────────

    return {
        init: init,
        saveProject: saveProject,
        loadProjectList: loadProjectList,
        loadProject: loadProject,
        exportTwiwcs: exportTwiwcs,
        importTwiwcs: importTwiwcs
    };
})();
