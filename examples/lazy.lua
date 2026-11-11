return {
  dir = vim.fn.expand("~/app/siren"),
  name = "siren.md",
  main = "siren",
  ft = "markdown",
  build = "npm ci --ignore-scripts",
  opts = {
    snacks_preview = false,
    font = "Noto Sans CJK SC",
    colors = { ["--pele-bg"] = "#1e2326", ["--pele-fg"] = "#d3c6aa" },
  },
}
