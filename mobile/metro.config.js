const { getDefaultConfig } = require("expo/metro-config");
const path = require("path");

const config = getDefaultConfig(__dirname);
// Let Metro see the shared sample data + grade math in ../lib (also used by the website).
config.watchFolders = [...(config.watchFolders ?? []), path.resolve(__dirname, "../lib")];

module.exports = config;
