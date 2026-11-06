import Foundation

public extension Library {
    @discardableResult
    func removeGeneratedSongIntroSlides() throws -> Int {
        var removed = 0
        for id in try store.ids(of: .presentation) {
            let document = try open(Presentation.self, id: id)
            let presentation = document.value
            guard let sectionID = generatedBlankIntroSectionID(in: presentation) else { continue }

            try document.update { presentation in
                presentation.slides.removeFirst()
                guard !presentation.slides.contains(where: { $0.sectionId == sectionID }) else {
                    return
                }
                presentation.sections?.removeAll { $0.id == sectionID }
                if var arrangements = presentation.arrangements {
                    for index in arrangements.indices {
                        arrangements[index].sectionIds.removeAll { $0 == sectionID }
                    }
                    presentation.arrangements = arrangements
                }
            }
            try save(document)
            removed += 1
        }
        return removed
    }
}

private func generatedBlankIntroSectionID(in presentation: Presentation) -> String? {
    guard presentation.presentationKind == .song,
          let source = presentation.reflowSource,
          !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let firstSlide = presentation.slides.first,
          isGeneratedBlankSlide(firstSlide),
          let sectionID = firstSlide.sectionId,
          presentation.sections?.first?.id == sectionID,
          let section = presentation.sections?.first(where: { $0.id == sectionID }),
          Reflow.isIntro(section.name)
    else { return nil }

    let sourceBody = LyricTextImporter.normalize(source).body
    guard let sourceFirstSection = Reflow.parse(sourceBody, linesPerSlide: 1).sections.first,
          !Reflow.isIntro(sourceFirstSection.name)
    else { return nil }

    return sectionID
}

private func isGeneratedBlankSlide(_ slide: Slide) -> Bool {
    slide.name.isEmpty
        && slide.objects.isEmpty
        && slide.background == nil
        && slide.backgroundFill == nil
        && slide.folder == nil
        && slide.themeId == nil
        && slide.unthemed == nil
        && slide.overrideDesigns == nil
        && slide.actions == nil
        && slide.notes == nil
        && slide.autoAdvance == nil
        && slide.transition == nil
        && slide.animationOrder == nil
        && slide.buildOrder == nil
        && slide.keepWords == nil
        && slide.history == nil
}
