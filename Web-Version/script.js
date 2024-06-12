document.addEventListener('DOMContentLoaded', () => {
    const gridDisplay = document.querySelector('#gridContainer');
    const scoreDisplay = document.getElementById('score');
    const highScoreDisplay = document.getElementById('highScore');
    const size = 4;

    let squares = [];
    let score = 0;
    let highScore = parseInt(localStorage.getItem('highScore')) || 0;
    let touchStartX = 0;
    let touchStartY = 0;
    let touchEndX = 0;
    let touchEndY = 0;

    highScoreDisplay.innerHTML = highScore;

    function createBoard() {
        for (let i = 0; i < size * size; i++) {
            let square = document.createElement('div');
            square.innerHTML = '';
            gridDisplay.appendChild(square);
            squares.push(square);
            updateCellValue(square, 0);
        }
        generateRandom();
        generateRandom();
    }

    function updateCellValue(cell, value) {
        cell.innerHTML = value > 0 ? value : '';
        cell.className = value > 0 ? 'cell' : 'cell placeholder';
        cell.setAttribute('data-value', value);

        if (value > 0) {
            cell.classList.add('pop');
            setTimeout(() => cell.classList.remove('pop'), 150);
        }
    }

    function generateRandom() {
        let filledSquares = squares.filter(square => parseInt(square.getAttribute('data-value')) !== 0);
        if (filledSquares.length === size * size) return checkForGameOver();

        let randomNumber = Math.floor(Math.random() * squares.length);
        let randomSquare = squares[randomNumber];
        if (randomSquare.getAttribute('data-value') === '0') {
            const value = Math.random() > 0.9 ? 4 : 2;
            updateCellValue(randomSquare, value);
        } else {
            generateRandom();
        }
    }

    function slideRow(row) {
        let filteredRow = row.filter(num => num);
        let missing = size - filteredRow.length;
        let zeros = Array(missing).fill(0);
        return zeros.concat(filteredRow);
    }

    function combineRow(row) {
        for (let i = 0; i < row.length - 1; i++) {
            if (row[i] === row[i + 1] && row[i] !== 0) {
                row[i] *= 2;
                row[i + 1] = 0;
                score += row[i];
                scoreDisplay.innerHTML = score;
                if (score > highScore) {
                    highScore = score;
                    localStorage.setItem('highScore', highScore);
                    highScoreDisplay.innerHTML = highScore;
                }
            }
        }
        return row;
    }

    function moveRight() {
        for (let i = 0; i < size * size; i += size) {
            let row = [];
            for (let j = 0; j < size; j++) {
                row.push(parseInt(squares[i + j].getAttribute('data-value')));
            }

            row = slideRow(row);
            row = combineRow(row);
            row = slideRow(row);

            for (let j = 0; j < size; j++) {
                updateCellValue(squares[i + j], row[j]);
            }
        }
    }

    function moveLeft() {
        for (let i = 0; i < size * size; i += size) {
            let row = [];
            for (let j = 0; j < size; j++) {
                row.push(parseInt(squares[i + j].getAttribute('data-value')));
            }

            row.reverse();
            row = slideRow(row);
            row = combineRow(row);
            row = slideRow(row);
            row.reverse();

            for (let j = 0; j < size; j++) {
                updateCellValue(squares[i + j], row[j]);
            }
        }
    }

    function moveDown() {
        for (let i = 0; i < size; i++) {
            let column = [];
            for (let j = 0; j < size; j++) {
                column.push(parseInt(squares[i + j * size].getAttribute('data-value')));
            }

            column = slideRow(column.reverse());
            column = combineRow(column);
            column = slideRow(column).reverse();

            for (let j = 0; j < size; j++) {
                updateCellValue(squares[i + j * size], column[j]);
            }
        }
    }

    function moveUp() {
        for (let i = 0; i < size; i++) {
            let column = [];
            for (let j = 0; j < size; j++) {
                column.push(parseInt(squares[i + j * size].getAttribute('data-value')));
            }

            column = slideRow(column);
            column = combineRow(column);
            column = slideRow(column);

            for (let j = 0; j < size; j++) {
                updateCellValue(squares[i + j * size], column[j]);
            }
        }
    }

    function control(e) {
        switch (e.keyCode) {
            case 39:
                moveRight();
                generateRandom();
                break;
            case 37:
                moveLeft();
                generateRandom();
                break;
            case 40:
                moveUp();
                generateRandom();
                break;
            case 38:
                moveDown();
                generateRandom();
                break;
        }
        checkForWin();
    }

    function resetGame() {
        createBoard();
    }

    function checkForWin() {
        for (let square of squares) {
            if (square.getAttribute('data-value') == 2048) {
                alert('You win!');
                document.removeEventListener('keyup', control);
                return;
            }
        }
    }

    function checkForGameOver() {
        let zeros = squares.filter(square => square.getAttribute('data-value') == '0').length;
        if (zeros === 0) {
            alert('Game over!');
            document.removeEventListener('keyup', control);
            window.location.reload();
        }
    }

    function handleTouchStart(event) {
        touchStartX = event.touches[0].clientX;
        touchStartY = event.touches[0].clientY;
    }

    function handleTouchMove(event) {
        touchEndX = event.changedTouches[0].clientX;
        touchEndY = event.changedTouches[0].clientY;
    }

    function handleTouchEnd() {
        const xDiff = touchEndX - touchStartX;
        const yDiff = touchEndY - touchStartY;

        if (Math.abs(xDiff) > Math.abs(yDiff)) {
            if (xDiff > 0) {
                moveRight();
            }
            else {
                moveLeft();
            }
        }
        else {
            if (yDiff > 0) {
                moveUp();
            }
            else {
                moveDown();
            }
        }
        generateRandom();
        checkForWin();
    }

    gridDisplay.addEventListener('touchstart', handleTouchStart, false);
    gridDisplay.addEventListener('touchmove', handleTouchMove, false);
    gridDisplay.addEventListener('touchend', handleTouchEnd, false);

    document.addEventListener('keyup', control);
    createBoard();
});
