import Charts
import SwiftUI

struct ParetoComparisonView: View {
    let projection: WorkspaceProjection
    @State private var preset: ParetoPreset = .qualityCost

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pareto 对比").font(.title2.bold())
                Spacer()
                Picker("预设", selection: $preset) {
                    ForEach(ParetoPreset.allCases) { Text($0.name).tag($0) }
                }
                .frame(width: 220)
            }
            Text(preset.explanation).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            AnalysisExplanation()
            Chart(plottable) { point in
                PointMark(
                    x: .value(preset.horizontalLabel, point.consumption),
                    y: .value(
                        projection.source.id == .sweBenchVerified ? "% Resolved" : "质量（越高越好）",
                        point.quality
                    )
                )
                .foregroundStyle(by: .value("状态", point.classification.label))
                .symbol(by: .value("状态", point.classification.label))
                .annotation(position: .top) { Text(point.displayName).font(.caption2) }
            }
            .frame(minHeight: 260)
            ForEach(results) { result in
                HStack {
                    Text(result.displayName)
                    Spacer()
                    if let model = model(for: result.modelID),
                       let costPerTask = DerivedMetrics.evaluate(model: model).first {
                        Text("\(costPerTask.formula.name)：\(RadarFormat.derived(costPerTask.value)) · \(costPerTask.formula.unit)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(result.classification.label)
                }
                .foregroundStyle(result.classification == .dataInsufficient ? .secondary : .primary)
            }
            Text("仅当前数据集 · \(projection.sync?.benchmark.value?.seriesRevision ?? "—") · 不含社区评分与来源额度")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    private var results: [ParetoResult] { projection.pareto(preset) }
    private func model(for id: ModelID) -> ModelBenchmark? {
        projection.sync?.benchmark.value?.models.first { $0.id == id }
    }
    private var plottable: [ParetoChartPoint] {
        results.compactMap { result in
            guard let quality = result.quality, let consumption = result.consumption else { return nil }
            return .init(
                id: result.modelID,
                displayName: result.displayName,
                quality: NSDecimalNumber(decimal: quality).doubleValue,
                consumption: NSDecimalNumber(decimal: consumption).doubleValue,
                classification: result.classification
            )
        }
    }
}

private struct ParetoChartPoint: Identifiable {
    let id: ModelID
    let displayName: String
    let quality: Double
    let consumption: Double
    let classification: ParetoClassification
}
