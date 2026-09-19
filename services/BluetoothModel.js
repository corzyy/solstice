// Pure helpers for BluetoothService/Panel — ported from
// AROICE-HQ/omarchy-bluetooth Model.js (MIT).
// No Qt imports here: plain JS so services and panels can share it.

function deviceLabel(device) {
    if (!device)
        return "";
    return String(device.deviceName || device.name || "").trim();
}

function toArray(values) {
    if (!values)
        return [];
    if (Array.isArray(values))
        return values.slice();
    var length = Number(values.length || 0);
    if (!isFinite(length) || length <= 0)
        return [];
    var list = [];
    for (var i = 0; i < length; i++)
        list.push(values[i]);
    return list;
}

function isUuidLike(value) {
    var text = String(value || "").trim();
    if (text === "")
        return false;
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)
        || /^[0-9a-f]{32}$/i.test(text)
        || /^0x[0-9a-f]{4,32}$/i.test(text)
        || /^0000[0-9a-f]{4}-0000-1000-8000-00805f9b34fb$/i.test(text);
}

function isAddressLike(value) {
    var text = String(value || "").trim();
    return /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(text);
}

function normalizedAddress(value) {
    return String(value || "").trim().toLowerCase().replace(/[^0-9a-f]/g, "");
}

function hasHumanName(device) {
    var label = deviceLabel(device);
    return label !== "" && !isUuidLike(label) && !isAddressLike(label);
}

function nodeProps(node) {
    return node && node.ready && node.properties ? node.properties : {};
}

function nodeText(node) {
    var props = nodeProps(node);
    return [
        node ? node.name : "",
        node ? node.description : "",
        node ? node.nickname : "",
        node ? node.nick : "",
        props["node.name"],
        props["node.description"],
        props["node.nick"],
        props["device.name"],
        props["device.description"],
        props["device.product.name"],
        props["device.alias"],
        props["device.string"],
        props["api.bluez5.address"],
        props["bluez5.address"],
        props["media.name"]
    ].join(" ").toLowerCase();
}

function bluetoothSinkMatchesDevice(node, device) {
    if (!node || !node.isSink || node.isStream || !device)
        return false;
    var address = normalizedAddress(device.address);
    var text = nodeText(node);
    if (address !== "" && normalizedAddress(text).indexOf(address) !== -1)
        return true;
    var label = deviceLabel(device).toLowerCase();
    return label !== "" && text.indexOf(label) !== -1;
}

function sortedByLabel(devices) {
    var list = toArray(devices);
    list.sort(function (a, b) {
        return deviceLabel(a).localeCompare(deviceLabel(b));
    });
    return list;
}

// Primitives-only projection of a BlueZ device for list-model rows. Holding
// the Device QObject in model data puts a live wrapper into every delegate's
// var property, and BlueZ churn (discovery timeouts, unpair) can destroy the
// object while a delegate is still incubating, which segfaults quickshell.
// Actions resolve the backend object by address instead.
function deviceRow(d) {
    if (!d)
        return null;
    var addr = d.address || "";
    var label = deviceLabel(d);
    return {
        address: addr,
        mac: addr,
        name: d.name || "",
        deviceName: d.deviceName || "",
        label: label !== "" ? label : addr,
        connected: !!d.connected,
        paired: !!d.paired,
        bonded: !!d.bonded,
        trusted: !!d.trusted,
        pairing: !!d.pairing,
        state: d.state !== undefined ? d.state : -1,
        batteryAvailable: !!d.batteryAvailable,
        battery: d.battery !== undefined ? d.battery : 0
    };
}

function remembered(row) {
    return !!row && (!!row.paired || !!row.bonded || !!row.trusted);
}

function deviceLists(devices) {
    var values = toArray(devices);
    var connected = [];
    var known = [];
    var discovered = [];
    for (var i = 0; i < values.length; i++) {
        var d = values[i];
        if (!d)
            continue;
        // Connected devices always show (with address fallback) — hiding
        // one would strand it with no way to disconnect.
        if (d.connected)
            connected.push(d);
        else if (!hasHumanName(d))
            continue;
        else if (d.paired || d.bonded || d.trusted)
            known.push(d);
        else
            discovered.push(d);
    }
    return {
        connected: sortedByLabel(connected),
        known: sortedByLabel(known),
        discovered: sortedByLabel(discovered)
    };
}

function cloneMap(map) {
    var next = ({});
    for (var key in map || {})
        next[key] = map[key];
    return next;
}

function pendingAction(actions, address) {
    return address && actions && actions[address] ? actions[address] : "";
}

function withPendingAction(actions, address, action) {
    var next = cloneMap(actions);
    if (!address)
        return next;
    if (action)
        next[address] = action;
    else
        delete next[address];
    return next;
}
