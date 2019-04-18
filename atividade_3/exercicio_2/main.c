#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <stdio.h>
#include <pthread.h>
#include <sys/time.h>

// Lê o conteúdo do arquivo filename e retorna um vetor E o tamanho dele
// Se filename for da forma "gen:%d", gera um vetor aleatório com %d elementos
//
// +-------> retorno da função, ponteiro para vetor malloc()ado e preenchido
// | 
// |         tamanho do vetor (usado <-----+
// |         como 2o retorno)              |
// v                                       v
double* load_vector(const char* filename, int* out_size);

// Avalia o resultado no vetor c. Assume-se que todos os ponteiros (a, b, e c)
// tenham tamanho size. 
void avaliar(double* a, double* b, double* c, int size);

typedef struct {
    int init;
    int end;
    double* a;
    double* b;
    double* c;
} args_struct;

void* sumVectors(void *args) {
    args_struct* actual_args = args;

    int init = actual_args->init;
    int end = actual_args->end;
    double* a = actual_args->a;
    double* b = actual_args->b;
    double* c = actual_args->c;

    for (int i = init; i < end; i++) {
        c[i] = a[i] + b[i];
    }

    pthread_exit(0);
}

int main(int argc, char* argv[]) {
    srand(time(NULL));

    //Temos argumentos suficientes?
    if(argc < 4) {
        printf("Uso: %s n_threads a_file b_file [-silent]\n"
               "    n_threads    número de threads a serem usadas na computação\n"
               "    *_file       caminho de arquivo ou uma expressão com a forma gen:N,\n"
               "                 representando um vetor aleatório de tamanho N\n",
               argv[0]);
        return 1;
    }
  
    //Quantas threads?
    int n_threads = atoi(argv[1]);
    if (!n_threads) {
        printf("Número de threads deve ser > 0\n");
        return 1;
    }
    //Lê números de arquivos para vetores alocados com malloc
    int a_size = 0, b_size = 0;
    double* a = load_vector(argv[2], &a_size);
    if (!a) {
        //load_vector não conseguiu abrir o arquivo
        printf("Erro ao ler arquivo %s\n", argv[2]);
        return 1;
    }
    double* b = load_vector(argv[3], &b_size);
    if (!b) {
        printf("Erro ao ler arquivo %s\n", argv[3]);
        return 1;
    }
    
    //Garante que entradas são compatíveis
    if (a_size != b_size) {
        printf("Vetores a e b tem tamanhos diferentes! (%d != %d)\n", a_size, b_size);
        return 1;
    }
    //Cria vetor do resultado 
    double* c = malloc(a_size*sizeof(double));

    // Calcula com uma thread só. Programador original só deixou a leitura 
    // do argumento e fugiu pro caribe. É essa computação que você precisa 
    // paralelizar
    

    if(n_threads > a_size) {
        n_threads = a_size;
    }
    pthread_t threads[n_threads];

    int divInteger = a_size / n_threads;

    int divRest = a_size % n_threads;

    // Criando a estrutura para segurar os valores
    args_struct args_t[n_threads];

    for (int i = 0; i < n_threads; i++) {
        args_t[i].a = a;
        args_t[i].b = b;
        args_t[i].c = c;
        args_t[i].init = divInteger*i;
        args_t[i].end = divInteger + divRest;

        pthread_create(&threads[i], NULL, sumVectors, &args_t[i]);

    }
    for (int i = 0; i < n_threads; i++) {
        pthread_join(threads[i], NULL);
        printf("Thread %ld encerrou.\n", threads[i]);
    }

    //    +---------------------------------+
    // ** | IMPORTANTE: avalia o resultado! | **
    //    +---------------------------------+
    avaliar(a, b, c, a_size);

    //Importante: libera memória
    free(a);
    free(b);
    free(c);

    return 0;
}
