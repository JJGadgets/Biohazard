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
    { "folke/tokyonight.nvim", lazy = false, priority = 1000, opts = { style = "night" }, config = function() vim.cmd([[colorscheme tokyonight-night]]); end, },
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
          --ensure_installed = 'all',
          ignore_install = { 'org' }, -- nvim-orgmode compatibility
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
    ---- folding
    { "kevinhwang91/nvim-ufo", dependencies = { "kevinhwang91/promise-async" }, event = { "BufReadPre", "BufNewFile" }, opts = {
      provider_selector = function(bufnr, filetype, buftype)
        return { "treesitter", "indent" } -- LSP takes too long to init
      end
    }},
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
        cmp.setup.filetype('gitcommit', {
          sources = cmp.config.sources({
            { name = 'conventionalcommits' },
            { name = 'commit' },
            { name = 'git' },
          }, {
            { name = "async_path" },
            { name = 'buffer' },
          })
        })
        cmp.setup.filetype('org', {
          sources = cmp.config.sources({
            { name = "orgmode" },
            { name = "async_path" },
            { name = 'buffer' },
          })
        })
        return {
          snippet = { expand = function(args) vim.snippet.expand(args.body); end, }, -- REQUIRED to specify snippet engine -- `vim.snippet` for native neovim snippets (Neovim v0.10+)
          sources = cmp.config.sources({ -- multiple tables is so the first table must have no results before the second table is shown, etc
          -- TODO: git sources
            { name = "nvim_lsp_signature_help" },
            { name = "nvim_lsp" },
            { name = "bufname" },
            { name = "async_path" },
            { name = "fish" },
          }, {
            { name = "buffer" },
          }),
          completion = { completeopt = "menu,menuone,noinsert" .. (auto_select and "" or ",noselect"), }, -- suggested config
          preselect = auto_select and cmp.PreselectMode.Item or cmp.PreselectMode.None, -- suggested config
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
          experimental = { ghost_text = { hl_group = "CmpGhostText", }, }, -- suggested config
          sorting = defaults.sorting, -- suggested config
        }
      end,
    },
    { "mtoohey31/cmp-fish", ft = "fish" },
    { "davidsierradz/cmp-conventionalcommits", ft = "gitcommit", },
    { "Dosx001/cmp-commit", ft = "gitcommit", },
    { "petertriho/cmp-git", ft = "gitcommit", },
    { "ray-x/lsp_signature.nvim", event = "VeryLazy", opts = {}, },
    -- LSP
    { "williamboman/mason.nvim", lazy = true },
    { "williamboman/mason-lspconfig.nvim", lazy = true, opts = { automatic_installation = true } },
    { "b0o/schemastore.nvim", lazy = true },
    { "diogo464/kubernetes.nvim", lazy = true, opts = {}, },
    { "someone-stole-my-name/yaml-companion.nvim",
    --{ "msvechla/yaml-companion.nvim",
    --  branch = "kubernetes_crd_detection",
      --event = "VeryLazy",
      ft = { "yaml" },
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
        local caps = function()
          local default_caps = vim.lsp.protocol.make_client_capabilities()
          default_caps.textDocument.completion = require('cmp_nvim_lsp').default_capabilities()['textDocument'].completion --- nvim-cmp completion
          --local default_caps = require('cmp_nvim_lsp').default_capabilities() --- nvim-cmp completion
          default_caps.textDocument.foldingRange = { dynamicRegistration = false, lineFoldingOnly = true } --- nvim-ufo folding
          return default_caps
        end
        -- lazy load Kubernetes.nvim
        local kubernetes_nvim_load = function()
          if vim.bo.filetype == "yaml" then return require('kubernetes').yamlls_schema(); else return ""; end
        end
        local yaml_schemas = {
          {
            name = 'Kubernetes.nvim',
            --description = 'Kubernetes schemas extracted from cluster by kubernetes.nvim',
            fileMatch = '*.yaml',
            url = kubernetes_nvim_load(),
            --fileMatch = { 'kube/*.yaml', 'k8s/*.yaml', 'kubernetes/*.yaml', '/tmp/kubectl-edit*.yaml', },
          },
          {
            name = 'Flux Kustomization',
            --description = 'Kubernetes CRD - Flux Kustomization v1',
            fileMatch = 'ks.yaml',
            url = "https://flux.jank.ing/kustomization-kustomize-v1.json",
          },
          {
            name = 'Flux HelmRelease',
            --description = 'Kubernetes CRD - Flux HelmRelease v2beta2',
            fileMatch = 'hr.yaml',
            url = "https://flux.jank.ing/helmrelease-helm-v2beta2.json",
          },
          --{ -- TODO: this seems to do nothing...? not sure how the MachineConfig schema is supposed to look like, but it doesn't look right?
          --  name = 'Talos Linux MachineConfig',
          --  fileMatch = '{*/clusterconfig/,/tmp/MachineConfigs.config.talos.dev-v1alpha1}*.yaml',
          --  url = "https://www.talos.dev/v1.7/schemas/v1alpha1_config.schema.json",
          --  --url = "https://raw.githubusercontent.com/siderolabs/talos/main/website/content/v1.7/schemas/config.schema.json",
          --},
        }
        local schemaStoreCatalog = {
          -- select subset from the JSON schema catalog
          'Talhelper',
          'kustomization.yaml',
          'Taskfile config',
          'Helm Chart.yaml',
          'Helm Chart.lock',
          'docker-compose.yml',
          'GitHub Workflow',
          'GitHub automatically generated release notes configuration',
        }
        local schemaStoreSelect = function(catalog)
          local schemaStoreSchemas = {}
          for k, v in pairs(catalog) do
            schemaStoreSchemas[k] = v
          end
          for _, v in ipairs(yaml_schemas) do
            table.insert(schemaStoreSchemas, v['name'])
          end
          return schemaStoreSchemas
        end
        local yamlCompanionSchemas = function()
          local ycSchemas = {}
          for _, v in ipairs(yaml_schemas) do
            table.insert(ycSchemas, {name = v['name'], uri = v['url']})
          end
          for _, v in ipairs(schemaStoreCatalog) do -- assumes 1 entry per catalog item
            local schemaUrl
            for k, _ in pairs(require('schemastore').yaml.schemas({select={v}})) do
              schemaUrl = k
              break
            end
            table.insert(ycSchemas, {name = v, uri = schemaUrl})
          end
          return ycSchemas
        end
        --- LSP servers config
        local yamlls_config = {
          capabilities = caps(),
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
              schemas = require('schemastore').yaml.schemas({
                extra = yaml_schemas,
                select = schemaStoreSelect(schemaStoreCatalog),
              }),
            },
          },
        }
        -- Run LSP server setup
        -- IMPORTANT: if the return of the args passed to setup has a parent {}, use `setup(arg)` where `arg = {...}` so the result is `setup{...}`, rather than `setup{arg}` which becomes `setup{{...}}`
        if vim.bo.filetype == "yaml" then lsp.yamlls.setup( require("yaml-companion").setup { builtin_matchers = { kubernetes = { enabled = true }, }, lspconfig = yamlls_config, schemas = yamlCompanionSchemas() } ); end
        lsp.taplo.setup { capabilities = caps(), settings = { evenBetterToml = { schema = { associations = {
          ['^\\.mise\\.toml$'] = 'https://mise.jdx.dev/schema/mise.json',
        }}}}}
        if vim.bo.filetype == "json" then lsp.jsonls.setup {
          capabilities = caps(),
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
        lsp.helm_ls.setup{capabilities = caps(),}
        lsp.lua_ls.setup{capabilities = caps(),}
        lsp.dockerls.setup{capabilities = caps(),}
        if vim.fn.executable('go') == 1 then lsp.gopls.setup{capabilities = caps(),} end
        lsp.tsserver.setup{capabilities = caps(),}
        lsp.pyright.setup{capabilities = caps(),}
      end
    },
    -- Org
    { 'nvim-orgmode/orgmode', ft = { 'org' }, opts = {
      org_agenda_files = '~/notes/**/*',
      org_default_notes_file = '~/notes/_inbox.org',
    }},
    --{ "chipsenkbeil/org-roam.nvim", ft = { "org" }, opts = {
    --  directory = "~/notes/Org/Roam",
    --  -- optional
    --  org_files = {"~/notes/**/*.org"}
    --}},
    { "akinsho/org-bullets.nvim", ft = { "org" }, opts = {} },
    { "lukas-reineke/headlines.nvim", ft = { "org" }, opts = {} }, -- uses treesitter
  },
  checker = { enabled = true, notify = false },
  -- default to latest stable semver
  --defaults = { version = "*" },
})

-- start rainbow_delimiters
vim.g.rainbow_delimiters = {}
-- use nvim-notify for notifications
vim.notify = require("notify")
-- nvim-ufo
vim.o.foldmethod = "manual" -- override vimrc value as that is meant for pluginless
vim.o.foldlevel = 99
vim.o.foldlevelstart = 99
vim.keymap.set('n', 'zR', require('ufo').openAllFolds)
vim.keymap.set('n', 'zM', require('ufo').closeAllFolds)
