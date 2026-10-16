return {
  {
    "mfussenegger/nvim-lint",
    opts = {
      linters_by_ft = {
        go = {}, -- disable it from nvim-lint
      },
    },
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        golangci_lint_ls = {},
        lua_ls = {
          settings = {
            Lua = {
              workspace = {
                library = {
                  "/usr/share/hypr/stubs",
                },
              },
            },
          },
        },
        qml_language_server = {
          cmd = { "qml-language-server" },
          filetypes = { "qml" },
          root_markers = { "shell.qml", "qmldir", ".git" },
        },
        ansiblels = {
          cmd = { "ansible-language-server", "--stdio" },
          filetypes = { "yaml.ansible" },
        },
      },
    },
  },
}
