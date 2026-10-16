package luasv

import "testing"

func TestParseSkipsByteOrderMark(t *testing.T) {
	vars, err := Parse([]byte("\xef\xbb\xbfTaxTheFoolsDB = {\n\t[\"a\"] = 1,\n}\n"))
	if err != nil {
		t.Fatalf("parse with BOM: %v", err)
	}
	if _, ok := vars["TaxTheFoolsDB"]; !ok {
		t.Fatalf("TaxTheFoolsDB missing")
	}
}
