if vim.fn.has("nvim-0.12") ~= 1 then
  error("base-tools requires Neovim 0.12+")
end

return { version = "0.1.4" }
