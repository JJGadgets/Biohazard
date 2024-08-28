-- Bootstrap lazy.nvim (https://github.com/folke/lazy.nvim/blob/09d4f0db23d0391760c9e1a0501e95e21678c11a/docs/installation.mdx?plain=1#L100-L144)
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

-- Vim setup here
-- Basic highly and backwards compatible plugin-less vimrc, including leader mappings for Lazy
vim.cmd("source ~/.vimrc")

-- Clipboard via OSC 52
vim.o.clipboard = "unnamedplus"
vim.g.clipboard = {
  name = 'OSC 52',
  copy = {
    ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
    ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
  },
  paste = {
    ['+'] = require('vim.ui.clipboard.osc52').paste('+'),
    ['*'] = require('vim.ui.clipboard.osc52').paste('*'),
  },
}

-- Setup lazy.nvim
require("lazy").setup({
  spec = {
    -- # Plugins
    -- colorscheme
    {
      "folke/tokyonight.nvim",
      lazy = false, -- make sure we load this during startup if it is your main colorscheme
      priority = 1000, -- make sure to load this before all the other start plugins
      opts = { style = "night" },
      -- load the colorscheme here
      config = function()
        vim.cmd([[colorscheme tokyonight-night]])
      end,
    },
    --- on-screen key prompts
    {
      "folke/which-key.nvim", event = "VeryLazy", opts = {} },
    -- rainbow indents
    { "HiPhish/rainbow-delimiters.nvim" },
    {
    	"lukas-reineke/indent-blankline.nvim",
    	dependencies = { "TheGLander/indent-rainbowline.nvim", },
      main = "ibl",
    	opts = function(_, opts)
    		-- Other blankline configuration here
        -- Load indent-rainbowline
    		return require("indent-rainbowline").make_opts(opts)
    	end,
    },
    --- Git UI
    { "lewis6991/gitsigns.nvim", opts = {
      --signs_staged_enable = true,
      signcolumn = true,
      numhl      = true,
      linehl     = true,
      word_diff  = true,
      current_line_blame = true,
      watch_gitdir = { follow_files = true },
    }},
    -- TreeSitter
    {
      "nvim-treesitter/nvim-treesitter",
      build = ":TSUpdate",
      config = function () 
        require("nvim-treesitter.configs").setup({
          ensure_installed = { "c", "lua", "vim", "vimdoc", "yaml", "go", "dockerfile", "fish", "bash", "python", "javascript", "typescript", "html", "css" },
          sync_install = false,
          highlight = { enable = true },
          indent = { enable = true },  
        })
      end
    },
    -- LSP
    { "williamboman/mason.nvim", lazy = true },
    { "williamboman/mason-lspconfig.nvim", lazy = true, opts = { automatic_installation = true } },
    { "b0o/schemastore.nvim", lazy = true },
    --{ "diogo464/kubernetes.nvim" },
    {
      "neovim/nvim-lspconfig",
      -- run lspconfig setup outside lazy stuff
      config = function(_, opts)
        -- Mason must load first? I know it's not the best way, but it's the simplest config lol
        require('mason').setup()
        if vim.fn.isdirectory(vim.fs.normalize('~/.local/share/nvim/mason/registries')) == 0 then vim.cmd('MasonUpdate'); end -- lazy.nvim build not working for this, only run on first init
        require('mason-lspconfig').setup{ automatic_installation = true }
        local lsp = require('lspconfig')
        lsp.yamlls.setup {
          format = true,
          opts = {
            capabilities = {
              textDocument = {
                foldingRange = {
                  dynamicRegistration = false,
                  lineFoldingOnly = true,
                },
              },
            },
            settings = {
              redhat = { telemetry = { enabled = false } },
              yaml = {
                format = {
                  enable = true,
                  singleQuote = false,
                },
                keyOrdering = false,
                completion = true,
                hover = true,
                validate = true,
                schemaStore = { enable = false, url = "" }, -- disable and set URL to null value to manually choose which SchemaStore, Kubernetes and custom schemas to use
                schemas = {
                  kubernetes = { "{pvc,deploy,sts,secret*,configmap,cm,cron*,rbac,ns,namespace,}.yaml" },
                  -- TODO: not working on Cosmic, presumably due to lazy loading or chaining or something
                  --[require('kubernetes').yamlls_schema()] = "*.yaml",
                  --[require('kubernetes').yamlls_schema()] = { "{pvc,deploy,sts,secret*,configmap,cm,cron*,rbac,ns,namespace,}.yaml" },
                  --[k8s_crds.yamlls_schema()] = "*.{yml,yaml}",
                  ["https://json.schemastore.org/github-workflow"] = ".github/workflows/*",
                  ["https://json.schemastore.org/kustomization"] = "kustomization.{yml,yaml}",
                  ["https://json.schemastore.org/chart"] = "Chart.{yml,yaml}",
                  ["https://flux.jank.ing/kustomization-kustomize-v1.json"] = "ks.{yml,yaml}",
                  ["https://flux.jank.ing/helmrelease-helm-v2beta2.json"] = "hr.{yml,yaml}",
                  ["https://crds.jank.ing/volsync.backube/replicationdestination_v1alpha1.json"] = "rdst.{yml,yaml}",
                  ["https://crds.jank.ing/volsync.backube/replicationsource_v1alpha1.json"] = "rsrc.{yml,yaml}",
                  ["https://crds.jank.ing/external-secrets.io/clustersecretstore_v1beta1.json"] = "clustersecretstore*.{yml,yaml}",
                  ["https://crds.jank.ing/external-secrets.io/externalsecret_v1beta1.json"] = "externalsecret*.{yml,yaml}",
                },
              },
            },
          },
        }
        lsp.taplo.setup{ settings = { evenBetterToml = { schema = { associations = {
          ['^\\.mise\\.toml$'] = 'https://mise.jdx.dev/schema/mise.json',
        }}}}}
        lsp.jsonls.setup {
          settings = {
            json = {
              validate = { enable = true },
              schemas = require('schemastore').json.schemas {
                select = {
                  'Renovate',
                  'GitHub Workflow Template Properties'
                }
              },
            }
          }
        }
        lsp.helm_ls.setup{}
        lsp.lua_ls.setup{}
        lsp.dockerls.setup{}
        lsp.gopls.setup{}
        lsp.tsserver.setup{}
        lsp.pyright.setup{}
      end
    },
  },
  -- Configure any other settings here. See the documentation for more details.
  -- colorscheme that will be used when installing plugins.
  install = { colorscheme = { "tokyonight" } },
  -- automatically check for plugin updates
  checker = { enabled = true },
  -- default to latest stable semver
  defaults = { version = "*" },
})

vim.g.rainbow_delimiters = {}

