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
local function normalPaste() -- restore non-OSC 52 paste
  return {
    vim.fn.split(vim.fn.getreg(""), "\n"),
    vim.fn.getregtype(""),
  }
end
vim.o.clipboard = "unnamedplus"
vim.g.clipboard = {
  name = 'OSC 52',
  copy = {
    ['+'] = require('vim.ui.clipboard.osc52').copy('+'),
    ['*'] = require('vim.ui.clipboard.osc52').copy('*'),
  },
  paste = {
    --['+'] = require('vim.ui.clipboard.osc52').paste('+'),
    --['*'] = require('vim.ui.clipboard.osc52').paste('*'),
    ['+'] = normalPaste,
    ['*'] = normalPaste,
  },
  cache_enabled = 1,
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
      signs_staged_enable = true,
      signcolumn = true,
      numhl      = true,
      linehl     = true,
      word_diff  = true,
      current_line_blame = true,
      watch_gitdir = { follow_files = true },
    }},
    -- notifications
    { "rcarriga/nvim-notify", event = "VeryLazy", opts = { stages = "static", render = "compact" } }, -- any animations will cause lag over remote connections, especially SSH via iSH on iOS
    -- UI stuff
    {
      "folke/noice.nvim",
      dependencies = { "MunifTanjim/nui.nvim", "rcarriga/nvim-notify", },
      event = "VeryLazy",
      opts = {
        -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
        lsp = { override = { ["vim.lsp.util.convert_input_to_markdown_lines"] = true, ["vim.lsp.util.stylize_markdown"] = true, ["cmp.entry.get_documentation"] = true, }, }, -- cmp option requires nvim_cmp
        -- suggested presets
        presets = {
          command_palette = true,
          long_message_to_split = true,
        },
      },
    },
    -- TreeSitter
    {
      "nvim-treesitter/nvim-treesitter",
      --branch = "master",
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
    -- telescope
    { "nvim-telescope/telescope.nvim" },
    -- Autocomplete
    {
      "hrsh7th/nvim-cmp",
      version = false, -- last release is way too old
      event = "InsertEnter",
      dependencies = {
        "hrsh7th/cmp-nvim-lsp",
        "hrsh7th/cmp-buffer",
        "hrsh7th/cmp-path",
      },
      opts = function()
        vim.api.nvim_set_hl(0, "CmpGhostText", { link = "Comment", default = true })
        local cmp = require("cmp")
        local defaults = require("cmp.config.default")()
        local auto_select = true
        return {
          snippet = {
            -- REQUIRED - you must specify a snippet engine
            expand = function(args)
              vim.snippet.expand(args.body) -- For native neovim snippets (Neovim v0.10+)
            end,
          },
          sources = cmp.config.sources({
            { name = "nvim_lsp" },
            { name = "path" },
          }, {
            { name = "buffer" },
          }),
          completion = {
            completeopt = "menu,menuone,noinsert" .. (auto_select and "" or ",noselect"),
          },
          preselect = auto_select and cmp.PreselectMode.Item or cmp.PreselectMode.None,
          experimental = {
            ghost_text = {
              hl_group = "CmpGhostText",
            },
          },
          sorting = defaults.sorting,
        }
      end,
    },
    -- LSP
    { "williamboman/mason.nvim", lazy = true },
    { "williamboman/mason-lspconfig.nvim", lazy = true, opts = { automatic_installation = true } },
    { "b0o/schemastore.nvim", lazy = true },
    { "diogo464/kubernetes.nvim", ft = { "yaml"}, opts = {}, },
    --{ "someone-stole-my-name/yaml-companion.nvim",
    { "msvechla/yaml-companion.nvim",
      ft = { "yaml"},
      branch = "kubernetes_crd_detection",
      dependancies = { "nvim-lua/plenary.nvim" },
      config = function()
        require("telescope").load_extension("yaml_schema")
      end,
    },
    {
      "neovim/nvim-lspconfig",
      event = { "FileType" },
      -- run lspconfig setup outside lazy stuff
      config = function(_, opts)
        -- Mason must load first? I know it's not the best way, but it's the simplest config lol
        require('mason').setup()
        if vim.fn.isdirectory(vim.fs.normalize('~/.local/share/nvim/mason/registries')) == 0 then vim.cmd('MasonUpdate'); end -- lazy.nvim build not working for this, only run on first init
        require('mason-lspconfig').setup{ automatic_installation = true }
        local lsp = require('lspconfig')
        local cmp_caps = require('cmp_nvim_lsp').default_capabilities()
        -- lazy load Kubernetes.nvim
        local kubernetes_nvim_load = function()
          if vim.bo.filetype == "yaml" then return require('kubernetes').yamlls_schema(); else return ""; end
        end
        --- LSP servers config
        local yamlls_schemas = { -- TODO: use same Lua table for yaml-companion and SchemaStore.nvim
          { name = "Kubernetes", fileMatch = "*.yaml", url = "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/master/v1.30.1-standalone-strict/all.json" },
          { name = "Flux HelmRelease", fileMatch = "hr.{y,ya}ml", url = "https://flux.jank.ing/helmrelease-helm-v2beta2.json" },
          { name = "Flux Kustomization", fileMatch = "ks.{y,ya}ml", url = "https://flux.jank.ing/kustomization-kustomize-v1.json" },
          { name = "VolSync ReplicationSource", fileMatch = "{rsrc,replicationsource}*.{y,ya}ml", url = "https://crds.jank.ing/volsync.backube/replicationsource_v1alpha1.json" },
          { name = "VolSync ReplicationDestination", fileMatch = "{rdst,replicationdestination}*.{y,ya}ml", url = "https://crds.jank.ing/volsync.backube/replicationdestination_v1alpha1.json" },
          { name = "ExternalSecret", fileMatch = "{es,externalsecret}*.{y,ya}ml", url = "https://crds.jank.ing/external-secrets.io/externalsecret_v1beta1.json" },
          { name = "ExternalSecret ClusterSecretStore", fileMatch = "{css|clustersecretstore*}.{y,ya}ml", url = "https://crds.jank.ing/external-secrets.io/clustersecretstore_v1beta1.json" },
        }
        local yamlls_config = {
          capabilities = cmp_caps,
          --capabilities = {
          --  textDocument = {
          --    foldingRange = {
          --      dynamicRegistration = false,
          --      lineFoldingOnly = true,
          --    },
          --  },
          --},
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
                --kubernetes = { "{pvc,deploy,sts,secret*,configmap,cm,cron*,rbac,ns,namespace}.yaml" },
                [kubernetes_nvim_load()] = "*.yaml",
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
        }
        -- Run LSP server setup
        -- IMPORTANT: if the return of the args passed to setup has a parent {}, use `setup(arg)` where `arg = {...}` so the result is `setup{...}`, rather than `setup{arg}` which becomes `setup{{...}}`
        if vim.bo.filetype == "yaml" then lsp.yamlls.setup( require("yaml-companion").setup { builtin_matchers = { kubernetes = { enabled = true }, kubernetes_crd = { enabled = true } }, lspconfig = yamlls_config, schemas = {} } ); end
        lsp.taplo.setup { settings = { evenBetterToml = { schema = { associations = {
          ['^\\.mise\\.toml$'] = 'https://mise.jdx.dev/schema/mise.json',
        }}}}}
        if vim.bo.filetype == "json" then lsp.jsonls.setup {
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
        }; end
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
  checker = { enabled = true, notify = false },
  -- default to latest stable semver
  --defaults = { version = "*" },
})

-- start rainbow_delimiters
vim.g.rainbow_delimiters = {}
-- use nvim-notify for notifications
vim.notify = require("notify")
