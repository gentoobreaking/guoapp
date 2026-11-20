package core

import (
	"testing"
	"time"
)

func testLibraryDrama(id, source, title string) LibraryDrama {
	return LibraryDrama{
		ID:             id,
		Source:         source,
		SourceID:       id,
		Title:          title,
		MetadataSchema: 1,
		Episodes:       10,
	}
}

func TestMergeNativeCatalogDeduplicatesByID(t *testing.T) {
	first := []LibraryDrama{
		testLibraryDrama("1", "hongguo", "第一部"),
		testLibraryDrama("2", "hongguo", "第二部"),
	}
	second := []LibraryDrama{
		testLibraryDrama("2", "hongguo", "第二部（更新）"),
		testLibraryDrama("3", "hongguo", "第三部"),
	}

	merged := mergeNativeCatalog(first, second)

	if len(merged) != 3 {
		t.Fatalf("預期 3 部，得到 %d", len(merged))
	}

	// ID 為 "2" 的應該被合併，標題以第二個為準
	var drama2 *LibraryDrama
	for i := range merged {
		if merged[i].ID == "2" {
			drama2 = &merged[i]
		}
	}
	if drama2 == nil {
		t.Fatal("ID 為 2 的劇集應該存在")
	}
	if drama2.Title != "第二部（更新）" {
		t.Errorf("預期標題為「第二部（更新）」，得到 %q", drama2.Title)
	}
}

func TestMergeNativeCatalogPreservesMissingFields(t *testing.T) {
	first := []LibraryDrama{
		testLibraryDrama("1", "hongguo", "第一部"),
	}
	second := []LibraryDrama{
		{ID: "1", Source: "hongguo", SourceID: "1", MetadataSchema: 1, Episodes: 20},
	}

	merged := mergeNativeCatalog(first, second)
	if len(merged) != 1 {
		t.Fatalf("預期 1 部，得到 %d", len(merged))
	}
	if merged[0].Title != "第一部" {
		t.Errorf("預期保留原標題「第一部」，得到 %q", merged[0].Title)
	}
	if merged[0].Episodes != 20 {
		t.Errorf("預期 Episodes 為 20，得到 %d", merged[0].Episodes)
	}
}

func TestMergeNativeCatalogEmpty(t *testing.T) {
	first := []LibraryDrama{testLibraryDrama("1", "hongguo", "第一部")}
	merged := mergeNativeCatalog(first, nil)
	if len(merged) != 1 {
		t.Fatalf("預期 1 部，得到 %d", len(merged))
	}

	merged = mergeNativeCatalog(nil, first)
	if len(merged) != 1 {
		t.Fatalf("預期 1 部，得到 %d", len(merged))
	}
}

func TestMergeNativeDramaFillsMissingFields(t *testing.T) {
	previous := testLibraryDrama("1", "hongguo", "原標題")
	previous.Description = "原描述"
	previous.Cover = "原封面"
	previous.Category = "原分類"

	fresh := LibraryDrama{
		ID:             "1",
		Source:         "hongguo",
		SourceID:       "1",
		MetadataSchema: 1,
	}

	merged := MergeNativeDrama(previous, fresh)
	if merged.Title != "原標題" {
		t.Errorf("預期保留原標題，得到 %q", merged.Title)
	}
	if merged.Description != "原描述" {
		t.Errorf("預期保留原描述，得到 %q", merged.Description)
	}
	if merged.Cover != "原封面" {
		t.Errorf("預期保留原封面，得到 %q", merged.Cover)
	}
	if merged.Category != "原分類" {
		t.Errorf("預期保留原分類，得到 %q", merged.Category)
	}
	if merged.Episodes != 10 {
		t.Errorf("預期保留原集數 10，得到 %d", merged.Episodes)
	}
}

func TestMergeNativeDramaDifferentID(t *testing.T) {
	previous := testLibraryDrama("1", "hongguo", "第一部")
	fresh := testLibraryDrama("2", "hongguo", "第二部")

	merged := MergeNativeDrama(previous, fresh)
	if merged.ID != "2" || merged.Title != "第二部" {
		t.Error("ID 不同時應該直接返回 fresh")
	}
}

func TestNativeGenericCategory(t *testing.T) {
	generic := []string{"短剧", "真人剧", "漫剧", "AI剧", "AI 剧", "AI短剧", "AI 短剧", "AI漫剧", "AI 漫剧"}
	for _, c := range generic {
		if !nativeGenericCategory(c) {
			t.Errorf("預期 %q 為通用分類", c)
		}
	}

	notGeneric := []string{"都市", "古装", "悬疑", ""}
	for _, c := range notGeneric {
		if nativeGenericCategory(c) {
			t.Errorf("預期 %q 不是通用分類", c)
		}
	}
}

func TestMigrateNativeDramaHuangdouVIP(t *testing.T) {
	drama := LibraryDrama{
		ID:             "1",
		Source:         "huangdou",
		SourceID:       "1",
		Title:          "測試",
		MetadataSchema: 0,
		VIP:            boolPtr(true),
	}
	migrated := migrateNativeDrama(drama)
	if migrated.MetadataSchema != 1 {
		t.Errorf("預期 MetadataSchema 為 1，得到 %d", migrated.MetadataSchema)
	}

	// VIP 為 true 應該保持不變
	if migrated.VIP == nil || !*migrated.VIP {
		t.Error("VIP 為 true 應該保持 true")
	}

	drama2 := LibraryDrama{
		ID:             "2",
		Source:         "huangdou",
		SourceID:       "2",
		Title:          "測試2",
		MetadataSchema: 0,
		VIP:            boolPtr(false),
	}
	migrated2 := migrateNativeDrama(drama2)
	if migrated2.VIP != nil {
		t.Error("huangdou 且 VIP 為 false 且 MetadataSchema 為 0，VIP 應該被設為 nil")
	}
}

func TestTrimNativeCatalogs(t *testing.T) {
	catalogs := map[string][]LibraryDrama{
		"hongguo": {
			testLibraryDrama("1", "hongguo", "第一部"),
			testLibraryDrama("2", "hongguo", "第二部"),
		},
	}

	// 小於上限，不應該修改
	trimNativeCatalogs(catalogs)
	if len(catalogs["hongguo"]) != 2 {
		t.Errorf("預期 2 部，得到 %d", len(catalogs["hongguo"]))
	}

	// 大於上限，應該裁剪
	bigCatalog := make([]LibraryDrama, nativeCatalogMaxItems+100)
	for i := range bigCatalog {
		bigCatalog[i] = testLibraryDrama(string(rune('a'+i%26)), "hongguo", "測試")
	}
	catalogs["big"] = bigCatalog
	trimNativeCatalogs(catalogs)
	if len(catalogs["big"]) != nativeCatalogMaxItems {
		t.Errorf("預期 %d 部，得到 %d", nativeCatalogMaxItems, len(catalogs["big"]))
	}
}

func boolPtr(b bool) *bool {
	return &b
}

var _ = time.Second
