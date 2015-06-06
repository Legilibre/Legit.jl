# Legit.jl -- Convert French law in LEGI format to Git & Markdown
# By: Emmanuel Raviart <emmanuel.raviart@data.gouv.fr>
#
# Copyright (C) 2015 Etalab
# https://github.com/etalab/Legit.jl
#
# The GitLegistique.jl package is licensed under the MIT "Expat" License.


module Legit


import Base: hash, isequal, isless

using ArgParse
using Biryani
using Biryani.DatesConverters
using Compat
using Dates: Date, DateTime, datetime2unix, Day
using LibGit2
using LightXML
using Slugify


include("converters.jl")
include("articles.jl")


function main()
  args = parse_command_line()

  if !args["dry-run"]
    @assert splitext(args["repository"])[end] == ".git"
    if ispath(args["repository"])
      @assert isdir(args["repository"])
      @assert iswritable(args["repository"])
    else
      mkpath(args["repository"])
    end
    repository = init_repo(args["repository"]; bare = true)
  end

  version_dir = joinpath(args["dir"], "texte", "version")
  version_filenames = readdir(version_dir)
  @assert length(version_filenames) == 1 "Directory $version_dir contains more than 1 file: $version_filenames."
  version_filename = version_filenames[1]
  version_xml_document = parse_file(joinpath(version_dir, version_filename))
  texte_version = Convertible(parse_xml_element(root(version_xml_document))) |> pipe(
    element_to_texte_version,
    require,
  ) |> to_value

  struct_dir = joinpath(args["dir"], "texte", "struct")
  struct_filenames = readdir(struct_dir)
  @assert length(struct_filenames) == 1 "Directory $struct_dir contains more than 1 file: $struct_filenames."
  struct_filename = struct_filenames[1]
  @assert(version_filename == struct_filename,
    "Filenames for struct and version differ: $struct_filename != $version_filename.")
  struct_xml_document = parse_file(joinpath(struct_dir, struct_filename))
  textelr = Convertible(parse_xml_element(root(struct_xml_document))) |> pipe(
    element_to_textelr,
    require,
  ) |> to_value

  # articles_tree = transform_structure_to_articles_tree(changed_by_changer, args["dir"], textelr["STRUCT"],
  #   texte_version["META"]["META_SPEC"]["META_TEXTE_VERSION"]["TITREFULL"])
  # if get(texte_version, "VISAS", nothing) != nothing
  #   unshift!(articles_tree.children, NonArticle("", texte_version["VISAS"]["CONTENU"]))
  # end
  # if get(texte_version, "SIGNATAIRES", nothing) != nothing
  #   push!(articles_tree.children, NonArticle("", texte_version["SIGNATAIRES"]["CONTENU"]))
  # end
  # print(all_in_one_commonmark(articles_tree))

  changed_by_changer = @compat Dict{Changer, Changed}()
  root_table_of_content = RootTableOfContent(texte_version, textelr)
  transform_structure_to_articles_tree(changed_by_changer, args["dir"], root_table_of_content)
  changers = sort(collect(keys(changed_by_changer)))

  if !args["dry-run"]
    latest_commit = nothing
    root_tree = nothing
    for changer in changers
      epoch = int64(datetime2unix(DateTime(changer.date)))
      time_offset = 0
      author_signature = Signature("République française", "info@data.gouv.fr", epoch, time_offset)
      committer_signature = author_signature
      changed = changed_by_changer[changer]

      tree_builder_by_table_of_content = @compat Dict{AbstractTableOfContent, GitTreeBuilder}()
      for article in changed.articles
        blob = blob_from_buffer(repository, all_in_one_commonmark(article))
        container = article.container
        tree_builder = get!(tree_builder_by_table_of_content, container) do
          if root_tree === nothing
            latest_tree = nothing
          elseif isa(container, RootTableOfContent)
            latest_tree = root_tree
          else
            entry = entry_bypath(root_tree, git_dir(container))
            latest_tree = entry === nothing ? nothing : lookup_tree(repository, Oid(entry))
          end
          return GitTreeBuilder(repository, latest_tree)
        end
        insert!(tree_builder, string("article_", article.dict["META"]["META_SPEC"]["META_ARTICLE"]["NUM"], ".md"),
          Oid(blob), int(0o100644))  # FILEMODE_BLOB
      end

      for article in changed.deleted_articles
        container = article.container
        tree_builder = get!(tree_builder_by_table_of_content, container) do
          if root_tree === nothing
            latest_tree = nothing
          else
            if isa(container, RootTableOfContent)
              latest_tree = root_tree
            else
              entry = entry_bypath(root_tree, git_dir(container))
              latest_tree = entry === nothing ? nothing : lookup_tree(repository, Oid(entry))
            end
          end
          return GitTreeBuilder(repository, latest_tree)
        end
        delete!(tree_builder, string("article_", article.dict["META"]["META_SPEC"]["META_ARTICLE"]["NUM"], ".md"))
      end

      root_tree_oid = nothing
      while !isempty(tree_builder_by_table_of_content)
        tables_of_content_to_build = Set(keys(tree_builder_by_table_of_content))
        for (table_of_content, tree_builder) in tree_builder_by_table_of_content
          if !isa(table_of_content, RootTableOfContent)
            container = table_of_content.container
            while true
              pop!(tables_of_content_to_build, container, nothing)
              if isa(container, RootTableOfContent)
                break
              end
              container = container.container
            end
          end
        end
        for table_of_content in tables_of_content_to_build
          tree_builder = pop!(tree_builder_by_table_of_content, table_of_content)
          if length(tree_builder) == 0
            tree_oid = nothing
          else
            tree_oid = write!(tree_builder)
          end
          if isa(table_of_content, RootTableOfContent)
            root_tree_oid = tree_oid
          else
            container = table_of_content.container
            @assert !(container in tree_builder_by_table_of_content)
            tree_builder = get!(tree_builder_by_table_of_content, container) do
              if root_tree === nothing
                latest_tree = nothing
              elseif isa(container, RootTableOfContent)
                latest_tree = root_tree
              else
                entry = entry_bypath(root_tree, git_dir(container))
                latest_tree = entry === nothing ? nothing : lookup_tree(repository, Oid(entry))
              end
              return GitTreeBuilder(repository, latest_tree)
            end
            if tree_oid === nothing
              delete!(tree_builder, dir_name(table_of_content))
            else
              insert!(tree_builder, dir_name(table_of_content), tree_oid, int(0o40000))  # FILEMODE_TREE
            end
          end
        end
      end

      root_tree = lookup_tree(repository, root_tree_oid)
      latest_commit_oid = commit(repository, "HEAD", changer.message, author_signature, committer_signature, root_tree,
        (latest_commit === nothing ? [] : [latest_commit])...)
      latest_commit = lookup_commit(repository, latest_commit_oid)
    end
  end
end


function parse_command_line()
  arg_parse_settings = ArgParseSettings()
  @add_arg_table arg_parse_settings begin
    "--verbose", "-v"
      action = :store_true
      help = "increase output verbosity"
    "--dry-run", "-d"
      action = :store_true
      help = "don't write anything"
    "dir"
      help = "path of LEGI dir containing a law"
      required = true
    "repository"
      help = "path of Git repository to create"
      required = true
  end
  return parse_args(arg_parse_settings)
end


main()


end # module
