# Legit.jl -- Convert French law in LEGI format to Git & Markdown
# By: Emmanuel Raviart <emmanuel.raviart@data.gouv.fr>
#
# Copyright (C) 2015 Etalab
# https://github.com/etalab/Legit.jl
#
# The Legit.jl package is licensed under the MIT "Expat" License.


module LegitReorderCommits


using ArgParse
using Compat
using Dates
using LibGit2
using LightXML  # Not used, but needed by include("articles.jl")
import Slugify  # Not used, but needed by include("articles.jl")


include("articles.jl")


function main()
  args = parse_command_line()

  @assert ispath(args["repository"])
  @assert isdir(args["repository"])
  @assert iswritable(args["repository"])
  repository = repo_discover(args["repository"])
  @assert lookup_branch(repository, "reordered") === nothing "A branch named \"reordered\" already exists."
  @assert !is_head_unborn(repository) "HEAD points to an unborn branch (aka a branch without commit)."
  head_reference = head(repository)
  head_commit_id = target(head_reference)
  reordered_reference = lookup_ref(repository, "REORDERED")
  if reordered_reference === nothing
    reordered_reference = create_ref(repository, "REORDERED", "refs/heads/reordered")
  else
    reordered_reference = set_symbolic_target(reordered_reference, "refs/heads/reordered")
  end
  @assert lookup_branch(repository, "reordered") === nothing  # The "reordered" branch doesn't exist yet.

  commits_by_message_by_time = @compat Dict{Int64, Dict{String, Array{GitCommit}}}()
  commits_count = 1
  current_commit = lookup_commit(repository, head_commit_id)
  while true
    current_committer = committer(current_commit)
    commits_by_message = get!(commits_by_message_by_time, current_committer.time) do
      return @compat Dict{String, Array{GitCommit}}()
    end
    commits = get!(commits_by_message, message(current_commit)) do
      return GitCommit[]
    end
    push!(commits, current_commit)

    if parent_count(current_commit) == 0
      break
    end
    commits_count += 1
    current_commit = parent(current_commit, 1)
  end

  latest_commit = nothing
  latest_root_tree = nothing
  times = sort(collect(keys(commits_by_message_by_time)))
  for time in times
    commits_by_message = commits_by_message_by_time[time]
    messages = sort(collect(keys(commits_by_message)))
    for message in messages
      println("Reordering $(unix2datetime(time)) \"$message\".")
      commits = commits_by_message[message]
      section_by_git_dir_names = @compat Dict{Tuple, Union(Section, UnparsedSection)}()
      tree_builder_by_git_dir_names = @compat Dict{Tuple, GitTreeBuilder}()
      for current_commit in commits
        merge(
          repository,
          (),
          GitTree(current_commit),
          parent_count(current_commit) == 0 ? nothing : GitTree(parent(current_commit, 1)),
          latest_root_tree,
          section_by_git_dir_names,
          tree_builder_by_git_dir_names,
        )
      end

      # Generate trees (up to root tree) from tree builders.
      root_tree_id = nothing
      while !isempty(tree_builder_by_git_dir_names)
        git_dirs_names_to_build = Set(keys(tree_builder_by_git_dir_names))
        for (git_dir_names, tree_builder) in tree_builder_by_git_dir_names
          while !isempty(git_dir_names)
            git_dir_names = git_dir_names[1 : end - 1]
            pop!(git_dirs_names_to_build, git_dir_names, nothing)
          end
        end
        for git_dir_names in git_dirs_names_to_build
          tree_builder = pop!(tree_builder_by_git_dir_names, git_dir_names)
          if length(tree_builder) == 0
            tree_id = nothing
          else
            # Update README.md before building tree from tree builder.
            section = section_by_git_dir_names[git_dir_names]
            child_by_name = @compat Dict{String, Node}()
            filter!(tree_builder) do entry
              if entry.name != "README.md"
                child_by_name[entry.name] = section.child_by_name[entry.name]
              end
              return false  # Keep item in tree.
            end
            section.child_by_name = child_by_name
            blob = blob_from_buffer(repository, commonmark(section, "flat"))
            insert!(tree_builder, "README.md", Oid(blob), int(0o100644))  # FILEMODE_BLOB

            tree_id = write!(tree_builder)
          end
          if isempty(git_dir_names)
            root_tree_id = tree_id
          else
            dir_name = git_dir_names[end]
            parent_git_dir_names = git_dir_names[1 : end - 1]
            @assert !(parent_git_dir_names in git_dirs_names_to_build)
            parent_tree_builder = tree_builder_by_git_dir_names[parent_git_dir_names]
            if tree_id === nothing
              delete!(parent_tree_builder, dir_name)
            else
              insert!(parent_tree_builder, dir_name, tree_id, int(0o40000))  # FILEMODE_TREE
            end
          end
        end
      end

      root_tree = lookup_tree(repository, root_tree_id)
      latest_commit_id = commit(repository, "REORDERED", message, author(commits[1]), committer(commits[1]),
        root_tree, (latest_commit === nothing ? [] : [latest_commit])...)
      latest_commit = lookup_commit(repository, latest_commit_id)
      latest_root_tree = root_tree
    end
  end

  # @show commits_count
  # @show length(commits_by_message_by_time)
  # @show Date(unix2datetime(times[1])) keys(commits_by_message_by_time[times[1]])
  # @show hex(times[end]) Date(unix2datetime(times[end])) keys(commits_by_message_by_time[times[end]])
end


function merge(repository::GitRepo, git_dir_names::Tuple, current_tree::GitTree, parent_tree::Union(GitTree, Nothing),
    latest_tree::Union(GitTree, Nothing), section_by_git_dir_names::Dict{Tuple, Union(Section, UnparsedSection)},
    tree_builder_by_git_dir_names::Dict{Tuple, GitTreeBuilder})
  # if Oid(first_tree) == Oid(second_tree)
  #   return first_tree
  # end
  tree_builder = get!(tree_builder_by_git_dir_names, git_dir_names) do
    return GitTreeBuilder(repository, latest_tree)
  end

  readme_entry = current_tree["README.md"]
  @assert readme_entry !== nothing
  current_section = get(section_by_git_dir_names, git_dir_names, nothing)
  if current_section === nothing
    section_by_git_dir_names[git_dir_names] = current_section = parse_section_commonmark(repository, readme_entry,"")
  else
    updated_current_section = parse_section_commonmark(repository, readme_entry, current_section.short_title)
    for (name, child_section) in updated_current_section.child_by_name
      current_section.child_by_name[name] = child_section
    end
  end
  if latest_tree !== nothing
    latest_entry = latest_tree["README.md"]
    latest_section = parse_section_commonmark(repository, latest_entry, current_section.short_title)
    for (name, child_section) in latest_section.child_by_name
      get!(current_section.child_by_name, name, child_section)  # Add section when it doesn't exist yet.
    end
  end

  for current_entry in current_tree
    current_name = current_entry.name
    if current_name == "README.md"
      continue
    end
    current_id = Oid(current_entry)
    parent_entry = parent_tree === nothing ? nothing : parent_tree[current_name]
    if parent_entry === nothing
      insert!(tree_builder, current_name, current_id, int(filemode(current_entry)))
    else
      parent_id = Oid(parent_entry)
      if current_id != parent_id
        if !isempty(git_dir_names) && (git_dir_names[end] in ("codes-en-vigueur", "codes-non-en-vigueur") ||
            ismatch(r"^\d{4}$", git_dir_names[end]))
          # Current is a document. Use current version, ignoring latest.
          insert!(tree_builder, current_name, current_id, int(filemode(current_entry)))
        else
          current_git_dir_names = tuple(git_dir_names..., current_name)
          latest_entry = latest_tree === nothing ? nothing : latest_tree[current_name]
          merge(repository, current_git_dir_names, lookup_tree(repository, current_id),
            lookup_tree(repository, parent_id),
            latest_entry === nothing ? nothing : lookup_tree(repository, Oid(latest_entry)),
            section_by_git_dir_names, tree_builder_by_git_dir_names)
        end
      end
    end
  end
  if parent_tree !== nothing
    for parent_entry in parent_tree
      parent_name = parent_entry.name
      if current_tree[parent_name] === nothing && tree_builder[parent_name] !== nothing
        delete!(tree_builder, parent_name)
      end
    end
  end
end


function parse_command_line()
  arg_parse_settings = ArgParseSettings()
  @add_arg_table arg_parse_settings begin
    "--verbose", "-v"
      action = :store_true
      help = "increase output verbosity"
    "repository"
      help = "path of Git repository to create"
      required = true
  end
  return parse_args(arg_parse_settings)
end


main()


end # module
