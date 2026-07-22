import ProjectDescription

// THROWAWAY. This manifest exists only so the quick-entry prototype can run on
// both platforms before the real scaffold (#10) lands. It is deliberately crude
// and decides nothing about the real project layout — see #3 for that survey.
let tuist = Tuist(
	project: .tuist(compatibleXcodeVersions: .upToNextMajor("26.0"))
)
