defmodule Hoverscript.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/dompdv/hoverscript"

  def project do
    [
      app: :hoverscript,
      name: "Hoverscript",
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      aliases: aliases()
    ]
  end

  def cli do
    [
      preferred_envs: [
        docs: :dev,
        "hex.build": :dev,
        "hex.publish": :dev
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:floki, "~> 0.38.4"},
      {:toml, "~> 0.7.0"},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Parser and converter for Hoverscript (.hvt), a lightweight structured markup language."
  end

  defp package do
    [
      name: "hoverscript",
      organization: [],
      files: ~w(lib mix.exs README.md LICENSE .formatter.exs),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "HexDocs" => "https://hexdocs.pm/hoverscript"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      output: "exdoc",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "doc/REFERENCE.md",
        "doc/BUILD.md",
        "doc/AST.md",
        "doc/ast/node_fields.md",
        "doc/ast/blocks.md",
        "doc/ast/lists.md",
        "doc/ast/inlines.md",
        "doc/ast/errors.md"
      ],
      groups_for_extras: [
        Introduction: ["README.md"],
        Hoverscript: ["doc/REFERENCE.md", "doc/BUILD.md"],
        AST: [
          "doc/AST.md",
          "doc/ast/node_fields.md",
          "doc/ast/blocks.md",
          "doc/ast/lists.md",
          "doc/ast/inlines.md",
          "doc/ast/errors.md"
        ]
      ]
    ]
  end

  defp aliases do
    [
      "docs.all": ["docs", "docs --open"]
    ]
  end
end
