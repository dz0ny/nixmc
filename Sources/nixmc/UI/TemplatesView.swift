import SwiftUI

/// Recipe browser. Recipes are bundled Markdown files, so adding one never
/// requires a Swift change unless it introduces a new sidebar section.
struct TemplatesView: View {
    let onPick: (Recipe) -> Void
    let onClose: () -> Void

    @ObservedObject private var teamRecipes = TeamRecipeStore.shared
    @State private var selected = RecipeCatalog.categories.first?.id ?? ""
    @State private var search = ""
    @State private var previewRecipe: Recipe?

    private var categories: [RecipeCategory] {
        guard !search.isEmpty else { return RecipeCatalog.categories }
        let q = search.lowercased()
        return RecipeCatalog.categories.compactMap { category in
            let hits = category.recipes.filter {
                $0.title.lowercased().contains(q)
                    || $0.summary.lowercased().contains(q)
                    || $0.body.lowercased().contains(q)
            }
            guard !hits.isEmpty || category.title.lowercased().contains(q) else { return nil }
            return RecipeCategory(id: category.id, title: category.title, symbol: category.symbol,
                                  summary: category.summary,
                                  recipes: category.title.lowercased().contains(q) ? category.recipes : hits)
        }
    }

    private var current: RecipeCategory? {
        categories.first { $0.id == selected } ?? categories.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HSplitView {
                categoryList
                    .frame(minWidth: 210, idealWidth: 230, maxWidth: 280)
                recipeList
                    .frame(minWidth: 420)
            }
        }
        .tint(Theme.accent)
        .frame(minWidth: 840, minHeight: 580)
        .sheet(item: $previewRecipe) { recipe in
            RecipePreviewSheet(
                recipe: recipe,
                onAddToChat: {
                    previewRecipe = nil
                    onPick(recipe)
                },
                onEditPrompt: nil
            )
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            BrandMark(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Recipes").font(.headline)
                Text("Implementation patterns you can review before sending.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search recipes", text: $search)
                    .textFieldStyle(.plain)
                    .frame(width: 170)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08)))
            Button("Done", action: onClose).keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private var categoryList: some View {
        List(selection: $selected) {
            ForEach(categories) { category in
                Label(category.title, systemImage: category.symbol).tag(category.id)
            }
        }
        .listStyle(.sidebar)
    }

    private var recipeList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let category = current {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(category.title, systemImage: category.symbol).font(.title3.bold())
                        Text(category.summary).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(category.recipes) { recipe in
                        RecipeRow(recipe: recipe) { previewRecipe = recipe }
                    }
                } else {
                    Text("No recipes match “\(search)”.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct RecipeRow: View {
    let recipe: Recipe
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(Theme.brandSoft).frame(width: 34, height: 34)
                Image(systemName: recipe.symbol).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(recipe.title).font(.subheadline.weight(.semibold))
                    if recipe.featured {
                        Text("Popular")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.brandSoft, in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                }
                Text(recipe.summary)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if recipe.source != nil {
                    Label("Includes source-backed implementation notes", systemImage: "curlybraces")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            Button("Use", action: action).buttonStyle(.brandCompact)
        }
        .padding(14)
        .card(hover: hover)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: action)
    }
}
