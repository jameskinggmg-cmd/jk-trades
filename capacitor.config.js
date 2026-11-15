const mode = process.env.JK_APP_MODE || "customer";
const apps = {
  customer: { appId: "uk.co.jktrades.customer", appName: "JK TRADES Customer" },
  trades: { appId: "uk.co.jktrades.trades", appName: "JK TRADES Tradesperson" },
  admin: { appId: "uk.co.jktrades.admin", appName: "JK TRADES Admin" }
};
if (!apps[mode]) throw new Error("JK_APP_MODE must be customer, trades or admin");
module.exports = {
  ...apps[mode],
  webDir: ".",
  server: {
    url: `https://jameskinggmg-cmd.github.io/jk-trades/?app=${mode}`,
    cleartext: false,
    androidScheme: "https"
  },
  android: { allowMixedContent: false }
};
