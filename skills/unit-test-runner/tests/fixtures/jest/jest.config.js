// T-1.3 fixture: minimal Jest config. Detector only checks file presence,
// not contents — but a real-looking stub avoids surprising future humans
// who open this file expecting actual Jest config.
module.exports = {
  testEnvironment: "node",
  testMatch: ["**/?(*.)+(spec|test).[jt]s?(x)"],
};
