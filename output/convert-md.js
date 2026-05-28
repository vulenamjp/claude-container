const mammoth = require("mammoth");
const fs = require("fs");
const path = require("path");

const dir = "/workspace/supportFiles/upload-1779782092704-2cf73096";
const files = fs.readdirSync(dir);
const docx = files.find(f => f.endsWith(".docx"));
const input = path.join(dir, docx);
const output = "/workspace/output/converted.md";

mammoth.convertToMarkdown({ path: input })
  .then(result => {
    fs.writeFileSync(output, result.value, "utf8");
    console.log("OK ->", output);
    console.log("MD length:", result.value.length);
  })
  .catch(err => { console.error("ERROR:", err.message); process.exit(1); });
