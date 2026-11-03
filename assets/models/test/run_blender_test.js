const { execSync } = require("child_process");
const path = require("path");

const blenderExe = "C:\\Program Files\\Blender Foundation\\Blender 5.2\\blender.exe";
const scriptPath = path.join("C:\\myGames\\tanks-vk", "blender_mcp_test.py");

try {
    const cmd = `"${blenderExe}" -P "${scriptPath}" --background`;
    console.log("Running:", cmd);
    const output = execSync(cmd, {
        cwd: "C:\\myGames\\tanks-vk",
        encoding: "utf8",
        timeout: 60000
    });
    console.log(output);
} catch (e) {
    console.error("ERROR:", e.message);
    if (e.stdout) console.log("STDOUT:", e.stdout.toString());
    if (e.stderr) console.error("STDERR:", e.stderr.toString());
    process.exit(1);
}
