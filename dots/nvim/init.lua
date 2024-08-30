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
    { "folke/tokyonight.nvim", lazy = false, priority = 1000, opts = { style = "night" }, config = function()
        -- load the colorscheme here
        vim.cmd([[colorscheme tokyonight-night]])
      end,
    },
    --- on-screen key prompts
    { "folke/which-key.nvim", event = "VeryLazy", opts = {} },
    -- rainbow indents
    { "HiPhish/rainbow-delimiters.nvim", event = { "BufReadPre", "BufNewFile" }, },
    { "lukas-reineke/indent-blankline.nvim",
      event = { "BufReadPre", "BufNewFile" },
    	dependencies = { "TheGLander/indent-rainbowline.nvim", },
      main = "ibl",
    	opts = function(_, opts)
    		-- Other blankline configuration here
        -- Load indent-rainbowline
    		return require("indent-rainbowline").make_opts(opts)
    	end,
    },
    --- Git UI
    { "lewis6991/gitsigns.nvim", event = { "BufReadPre", "BufNewFile" }, opts = {
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
    --{ "folke/noice.nvim",
    --  dependencies = { "MunifTanjim/nui.nvim", "rcarriga/nvim-notify", },
    --  event = "VeryLazy",
    --  opts = {
    --    -- override markdown rendering so that **cmp** and other plugins use **Treesitter**
    --    lsp = { override = { ["vim.lsp.util.convert_input_to_markdown_lines"] = true, ["vim.lsp.util.stylize_markdown"] = true, ["cmp.entry.get_documentation"] = true, }, }, -- cmp option requires nvim_cmp
    --    -- suggested presets
    --    presets = {
    --      command_palette = true,
    --      long_message_to_split = true,
    --    },
    --  },
    --},
    -- TreeSitter
    { "nvim-treesitter/nvim-treesitter",
      --branch = "master",
      event = "VeryLazy",
      build = ":TSUpdate",
      config = function()
        require("nvim-treesitter.configs").setup({
          ensure_installed = { "c", "lua", "vim", "vimdoc", "yaml", "go", "dockerfile", "fish", "bash", "python", "javascript", "typescript", "html", "css" },
          sync_install = false,
          highlight = { enable = true },
          indent = { enable = true },
        })
      end
    },
    -- telescope
    { "nvim-telescope/telescope.nvim", event = "VeryLazy", },
    -- auto brackets
    { 'windwp/nvim-autopairs', event = "InsertEnter", opts = {}, },
    -- Autocomplete
    { "hrsh7th/nvim-cmp",
      version = false, -- last release is way too old
      event = "InsertEnter",
      dependencies = {
        "hrsh7th/cmp-nvim-lsp",
        "hrsh7th/cmp-buffer",
        "hrsh7th/cmp-path",
        "hrsh7th/cmp-nvim-lsp-signature-help",
        "FelipeLema/cmp-async-path",
        "rasulomaroff/cmp-bufname",
      },
      opts = function()
        vim.api.nvim_set_hl(0, "CmpGhostText", { link = "Comment", default = true })
        local cmp = require("cmp")
        -- autopairs
        cmp.event:on('confirm_done', require('nvim-autopairs.completion.cmp').on_confirm_done())
        -- actual cmp config
        local defaults = require("cmp.config.default")()
        local auto_select = true
        return {
          snippet = {
            -- REQUIRED - you must specify a snippet engine
            expand = function(args)
              vim.snippet.expand(args.body) -- For native neovim snippets (Neovim v0.10+)
            end,
          },
          sources = cmp.config.sources({ -- TODO: git sources
            { name = "nvim_lsp_signature_help" },
            { name = "nvim_lsp" },
            { name = "bufname" },
            { name = "async_path" },
            { name = "fish" },
          }, {
            { name = "buffer" },
          }),
          completion = {
            completeopt = "menu,menuone,noinsert" .. (auto_select and "" or ",noselect"),
          },
          preselect = auto_select and cmp.PreselectMode.Item or cmp.PreselectMode.None,
          mapping = cmp.mapping.preset.insert({
            ['<C-b>'] = cmp.mapping.scroll_docs(-4),
            ['<C-f>'] = cmp.mapping.scroll_docs(4),
            ['<C-Space>'] = function()
              if cmp.visible() then cmp.abort(); else cmp.complete(); end
            end,
            ['<C-esc>'] = cmp.mapping.abort(),
            ['<C-c>'] = cmp.mapping.abort(),
            ['<CR>'] = cmp.mapping.confirm({ select = false }),
          }),
          experimental = {
            ghost_text = {
              hl_group = "CmpGhostText",
            },
          },
          sorting = defaults.sorting,
        }
      end,
    },
    { "mtoohey31/cmp-fish", ft = "fish" },
    { "ray-x/lsp_signature.nvim", event = "VeryLazy", opts = {}, },
    -- LSP
    { "williamboman/mason.nvim", lazy = true },
    { "williamboman/mason-lspconfig.nvim", lazy = true, opts = { automatic_installation = true } },
    { "b0o/schemastore.nvim", lazy = true },
    { "diogo464/kubernetes.nvim", lazy = true, opts = {}, },
    { "someone-stole-my-name/yaml-companion.nvim",
    --{ "msvechla/yaml-companion.nvim",
    --  branch = "kubernetes_crd_detection",
      ft = { "yaml"},
      dependancies = { "nvim-lua/plenary.nvim" },
      config = function()
        require("telescope").load_extension("yaml_schema")
      end,
    },
    { "neovim/nvim-lspconfig",
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
        local yamlls_config = {
          capabilities = cmp_caps,
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
        -- manual
        if vim.bo.filetype == "yaml" then lsp.yamlls.setup( require("yaml-companion").setup { builtin_matchers = { kubernetes = { enabled = true }, }, lspconfig = yamlls_config, schemas = {} } ); end
        --local lspsetup = function(lspserver, lspuserconfig)
        --  for _, v in ipairs(require('lspconfig')[lspserver].document_config.default_config.filetypes) do
        --    if vim.bo.filetype == v then
        --      require('lspconfig')[lspserver].setup(lspuserconfig)
        --    end
        --  end
        --end
        --lspsetup("yamlls", require("yaml-companion").setup { builtin_matchers = { kubernetes = { enabled = true }, }, lspconfig = yamlls_config, schemas = {} } )
        --local lsp_user_configs = {
        --  taplo = { settings = { evenBetterToml = { schema = { associations = {
        --    ['^\\.mise\\.toml$'] = 'https://mise.jdx.dev/schema/mise.json',
        --  }}}}},
        --  jsonls = {
        --    settings = {
        --      json = {
        --        validate = { enable = true },
        --        schemas = require('schemastore').json.schemas {
        --          select = {
        --            'Renovate',
        --            'GitHub Workflow Template Properties'
        --          }
        --        },
        --      }
        --    }
        --  },
        --  helm_ls = {},
        --  lua_ls = {},
        --  dockerls = {},
        --  gopls = {},
        --  tsserver = {},
        --  pyright = {},
        --}
        -- function to iterate configs and only setup on startup if current buffer is filetype, to avoid loading plugins required by LSP configs
        --for _, lspserver in ipairs(vim.tbl_keys(lsp_user_configs)) do -- normal lua pairs won't work as it will load the `require('plugin')`s
      end
    },
  },
  checker = { enabled = true, notify = false },
  -- default to latest stable semver
  --defaults = { version = "*" },
})

-- start rainbow_delimiters
vim.g.rainbow_delimiters = {}
-- use nvim-notify for notifications
vim.notify = require("notify")
