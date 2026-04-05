classdef test_Theme < matlab.unittest.TestCase
    % test_Theme  Unit tests for the Theme constants class.
    %
    % Run from the project root:
    %   >> runtests('tests/test_Theme')

    methods (TestClassSetup)
        function addProjectPaths(~)
            thisDir     = fileparts(mfilename('fullpath'));
            projectRoot = fullfile(thisDir, '..');
            addpath(fullfile(projectRoot, 'src', 'infrastructure', 'config'));
        end
    end

    methods (Test)

        % ── Base color constants ─────────────────────────────────────────

        function testColorBgIsRgbTriple(testCase)
            testCase.verifySize(Theme.COLOR_BG, [1 3], ...
                'COLOR_BG should be a 1x3 RGB vector');
            testCase.verifyTrue(all(Theme.COLOR_BG >= 0 & Theme.COLOR_BG <= 1), ...
                'COLOR_BG values should be in [0, 1]');
        end

        function testColorCardIsRgbTriple(testCase)
            testCase.verifySize(Theme.COLOR_CARD, [1 3]);
            testCase.verifyTrue(all(Theme.COLOR_CARD >= 0 & Theme.COLOR_CARD <= 1));
        end

        function testColorDividerIsRgbTriple(testCase)
            testCase.verifySize(Theme.COLOR_DIVIDER, [1 3]);
            testCase.verifyTrue(all(Theme.COLOR_DIVIDER >= 0 & Theme.COLOR_DIVIDER <= 1));
        end

        function testColorHeadingIsRgbTriple(testCase)
            testCase.verifySize(Theme.COLOR_HEADING, [1 3]);
            testCase.verifyTrue(all(Theme.COLOR_HEADING >= 0 & Theme.COLOR_HEADING <= 1));
        end

        function testColorLabelIsRgbTriple(testCase)
            testCase.verifySize(Theme.COLOR_LABEL, [1 3]);
            testCase.verifyTrue(all(Theme.COLOR_LABEL >= 0 & Theme.COLOR_LABEL <= 1));
        end

        function testColorMutedIsRgbTriple(testCase)
            testCase.verifySize(Theme.COLOR_MUTED, [1 3]);
            testCase.verifyTrue(all(Theme.COLOR_MUTED >= 0 & Theme.COLOR_MUTED <= 1));
        end

        % ── Accent color constants ───────────────────────────────────────

        function testColorPrimaryIsRgbTriple(testCase)
            testCase.verifySize(Theme.COLOR_PRIMARY, [1 3]);
            testCase.verifyTrue(all(Theme.COLOR_PRIMARY >= 0 & Theme.COLOR_PRIMARY <= 1));
        end

        function testColorSuccessIsRgbTriple(testCase)
            testCase.verifySize(Theme.COLOR_SUCCESS, [1 3]);
            testCase.verifyTrue(all(Theme.COLOR_SUCCESS >= 0 & Theme.COLOR_SUCCESS <= 1));
        end

        function testColorPurpleIsRgbTriple(testCase)
            testCase.verifySize(Theme.COLOR_PURPLE, [1 3]);
            testCase.verifyTrue(all(Theme.COLOR_PURPLE >= 0 & Theme.COLOR_PURPLE <= 1));
        end

        function testColorAmberIsRgbTriple(testCase)
            testCase.verifySize(Theme.COLOR_AMBER, [1 3]);
            testCase.verifyTrue(all(Theme.COLOR_AMBER >= 0 & Theme.COLOR_AMBER <= 1));
        end

        % ── Font size constants ──────────────────────────────────────────

        function testFontSizeSmIsPositive(testCase)
            testCase.verifyGreaterThan(Theme.FONT_SIZE_SM, 0);
            testCase.verifyClass(Theme.FONT_SIZE_SM, 'double');
        end

        function testFontSizeIsPositive(testCase)
            testCase.verifyGreaterThan(Theme.FONT_SIZE, 0);
        end

        function testFontSizeMdIsPositive(testCase)
            testCase.verifyGreaterThan(Theme.FONT_SIZE_MD, 0);
        end

        function testFontSizeLgIsPositive(testCase)
            testCase.verifyGreaterThan(Theme.FONT_SIZE_LG, 0);
        end

        function testFontSizeTitleIsPositive(testCase)
            testCase.verifyGreaterThan(Theme.FONT_SIZE_TITLE, 0);
        end

        function testFontSizeOrdering(testCase)
            testCase.verifyLessThanOrEqual(Theme.FONT_SIZE_SM, Theme.FONT_SIZE);
            testCase.verifyLessThanOrEqual(Theme.FONT_SIZE, Theme.FONT_SIZE_MD);
            testCase.verifyLessThanOrEqual(Theme.FONT_SIZE_MD, Theme.FONT_SIZE_LG);
            testCase.verifyLessThanOrEqual(Theme.FONT_SIZE_LG, Theme.FONT_SIZE_TITLE);
        end

        % ── Layout size constants ────────────────────────────────────────

        function testBtnRowHeightIsPositive(testCase)
            testCase.verifyGreaterThan(Theme.BTN_ROW_HEIGHT, 0);
            testCase.verifyClass(Theme.BTN_ROW_HEIGHT, 'double');
        end

        function testActionBarHeightIsPositive(testCase)
            testCase.verifyGreaterThan(Theme.ACTION_BAR_HEIGHT, 0);
        end

        function testBtnWidthIsPositive(testCase)
            testCase.verifyGreaterThan(Theme.BTN_WIDTH, 0);
        end

        function testDividerWidthIsPositive(testCase)
            testCase.verifyGreaterThan(Theme.DIVIDER_WIDTH, 0);
        end

        function testGridPaddingIsFourElement(testCase)
            testCase.verifySize(Theme.GRID_PADDING, [1 4], ...
                'GRID_PADDING should be a 1x4 vector');
            testCase.verifyTrue(all(Theme.GRID_PADDING >= 0));
        end

        function testGridRowSpacingIsPositive(testCase)
            testCase.verifyGreaterThan(Theme.GRID_ROW_SPACING, 0);
        end

        function testKpiInnerPadIsFourElement(testCase)
            testCase.verifySize(Theme.KPI_INNER_PAD, [1 4], ...
                'KPI_INNER_PAD should be a 1x4 vector');
        end

    end
end
