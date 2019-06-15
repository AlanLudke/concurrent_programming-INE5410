package br.ufsc.atividade10;

import javax.annotation.Nonnull;
import java.util.*;
import static br.ufsc.atividade10.Piece.Type.*;

public class Buffer {
    private final int maxSize;
    private int qtdX=0, qtdO=0;
    public LinkedList<Piece> buffer; 

    public Buffer() {
        this(10);
    }
    public Buffer(int maxSize) {
    	this.maxSize = maxSize;
        this.buffer = new LinkedList<Piece>();
    }

    public synchronized void add(Piece piece) throws InterruptedException {
       	if (piece.getType() == X) {
       		while(qtdX >= maxSize-2 || buffer.size() >= maxSize) {
       			wait();
       		}
            buffer.add(piece);
        	qtdX++;
//        	System.out.println("X adicionado");
            notifyAll();
       	}
       	else if (piece.getType() == O) {
       		while(qtdO >= maxSize-1 || buffer.size() >= maxSize) {
       			wait();
       		}
            buffer.add(piece);
        	qtdO++;
//        	System.out.println("O adicionado");
        	notifyAll();
       	}
    }

    public synchronized void takeOXO(@Nonnull List<Piece> xList,
                                     @Nonnull List<Piece> oList) throws InterruptedException {
        
        while (qtdO < 2 || qtdX < 1) {
            wait();
        }
//    	System.out.println("O: "+ qtdO + "\nX: "+ qtdX);

        Iterator<Piece> it = buffer.iterator();
        
        while(it.hasNext() && xList.size() < 1 || oList.size() < 2) {
    		Piece piece = it.next();

        	if(piece.getType() == X && xList.size() < 1) {
        		xList.add(piece);
	            qtdX--;
	        	it.remove();
	            notifyAll();
//	        	System.out.println("X removido");
        	} else if(piece.getType() == O && oList.size() < 2) {
        		oList.add(piece);
                qtdO--;
            	it.remove();
                notifyAll();
//            	System.out.println("O removido");
        	}
        }
    }
}
